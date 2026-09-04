# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAbandonAttempt < Dry::Operation
      TOOL_NAME = "attempt_abandon"
      POLICY_VERSION = "attempt-abandonment/v2"

      class PreparedV1 < Value
        attribute :abandoned_at, Types::Timestamp
        attribute :input_digest, Types::Sha256Digest
        attribute :resource_event_ids,
                  Types::Array.of(Types::UuidV7).constrained(min_size: 32, max_size: 32)
        attribute :attempt_event_id, Types::UuidV7
        attribute :work_item_event_id, Types::UuidV7
      end

      def initialize(
        event_store:,
        contract: Contracts::AbandonAttempt.new,
        decider: Domain::Attempts::Abandon.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        set_loader: WorkIntentionSetLoader.new(event_store:),
        intention_loader: WorkIntentionLoader.new(event_store:),
        resource_loader: WorkIntentionResourceLoader.new(event_store:),
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new
      )
        @event_store = event_store
        @contract = contract
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @set_loader = set_loader
        @intention_loader = intention_loader
        @resource_loader = resource_loader
        @repository_registration_loader = repository_registration_loader
        @repository_marker_builder = repository_marker_builder
      end

      def call(input)
        command = step prepare(input)
        step call_command(command)
      end

      def prepare(input)
        result = @contract.call(input)
        return Failure(invalid_input(result.errors.to_h)) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Success(
          Commands::AbandonAttempt.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            attempt_id: attributes.fetch(:attempt_id),
            reason: attributes.fetch(:reason)
          )
        )
      end

      def call_command(command, caused_by: nil)
        prepared = prepare_logical_values(command)
        steps do
          step @event_store.multiple { execute_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def invalid_input(details)
        OutcomeError.new(
          code: :invalid_input,
          message: "AbandonAttempt input is invalid",
          details:
        )
      end

      def prepare_logical_values(command)
        PreparedV1.new(
          abandoned_at: @clock.now,
          input_digest: @input_digest.call(command),
          resource_event_ids: 32.times.map { @id_generator.uuid_v7 },
          attempt_event_id: @id_generator.uuid_v7,
          work_item_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        steps do
          set_state = @set_loader.find_by_attempt(command.attempt_id) || Domain::WorkIntentions::SetState.initial
          member_states = set_state.members.map { @intention_loader.call(_1.intention_id).state }
          plan = step @decider.call(
            attempt_state: load_attempt_state(command.attempt_id),
            work_item_state: load_work_item_state(command.work_item_id),
            set_state:,
            member_states:,
            command:,
            abandoned_at: prepared.abandoned_at
          )
          persisted = step persist_domain_plan(
            plan,
            command:,
            prepared:,
            member_states:,
            caused_by:
          )
          Success(
            build_completion(
              command:,
              input_digest: prepared.input_digest,
              persisted_events: persisted,
              member_count: member_states.length,
              abandoned_at: prepared.abandoned_at
            )
          )
        end
      end

      def load_attempt_state(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          EventQueries::ATTEMPT_FOR_WORK_INTENTIONS
        ).map { deserialize(_1) }
        Domain::Attempts::State.reduce(events)
      end

      def load_work_item_state(work_item_id)
        events = @event_store.read_grouped(
          @stream_factory.work_item(work_item_id),
          GroupedEventReadCriteria.new(
            event_types: [
              "WorkItemCreated",
              "WorkItemAddedToChangeSet",
              "WorkItemAssignedToRepository",
              "WorkItemGoalDefined",
              "WorkItemAcceptanceCriteriaDefined",
              "WorkItemCompetitiveModeSelected",
              "WorkItemMadeReady",
              "WorkItemAcquired",
              "WorkItemRequeued",
              "WorkItemCandidateSelected",
              "WorkItemCompleted"
            ],
            direction: :desc
          )
        ).reverse.map { deserialize(_1) }
        Domain::WorkItems::State.reduce(events)
      end

      def persist_domain_plan(plan, command:, prepared:, member_states:, caused_by:)
        withdrawals = plan.events.grep(Events::ResourceWorkIntentionWithdrawnV1)
        event_ids = prepared.resource_event_ids.first(withdrawals.length) + [
          prepared.attempt_event_id,
          prepared.work_item_event_id
        ]
        resources = load_resources(member_states.select { |state| withdrawals.any? { _1.intention_id == state.intention_id } })
        return resources if resources.failure?

        persisted = plan.writes.zip(event_ids).map do |write, event_id|
          event = write.event
          physical = @event_factory.build!(
            event:,
            event_id:,
            metadata: command_metadata(command),
            markers: event_markers(command, event, member_states:, resources: resources.value!),
            caused_by:
          )
          @event_store.append(write.stream, [ physical ]).fetch(0)
        end
        Success(persisted)
      end

      def load_resources(states)
        resources = states.map do |state|
          target = ResourceLeaseTargetV1.new(
            resource_id: state.resource_id,
            base_blob_oid: state.base_blob_oid
          )
          result = @resource_loader.call(target, repository_id: state.repository_id)
          return result if result.failure?

          registration = @repository_registration_loader.call(state.repository_id)
          return repository_not_registered(state.repository_id) unless registration

          [ state.intention_id, result.value!, registration ]
        end
        Success(resources)
      end

      def event_markers(command, event, member_states:, resources:)
        common = [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "command:#{command.command_id}"
        ]
        return common unless event.is_a?(Events::ResourceWorkIntentionWithdrawnV1)

        state = member_states.find { _1.intention_id == event.intention_id }
        _intention_id, resource, registration = resources.find { _1.first == event.intention_id }
        common + [
          "work-intention-set:#{state.set_id}",
          "work-intention:#{state.intention_id}",
          "resource:#{state.resource_id}",
          "resource-kind:#{resource.kind}",
          *@repository_marker_builder.call(registration),
          *@repository_marker_builder.work_intention_event_markers(
            repository_id: state.repository_id,
            resource_path: resource.path
          )
        ]
      end

      def build_completion(command:, input_digest:, persisted_events:, member_count:, abandoned_at:)
        withdrawn_count = persisted_events.count { _1.type == "ResourceWorkIntentionWithdrawn" }
        untouched_count = member_count - withdrawn_count
        warnings = [ "Reacquire the WorkItem with a fresh Attempt ID and base snapshot before resuming." ]
        if untouched_count.positive?
          warnings << "#{untouched_count} work intention(s) were already inactive and were left unchanged."
        end

        CommandResultV1.new(
          command_id: command.command_id,
          tool_name: TOOL_NAME,
          canonical_input_digest: input_digest,
          status: "ok",
          summary: "Attempt abandoned; WorkItem requeued; #{withdrawn_count} active work intention(s) withdrawn.",
          receipt: command.command_id,
          data: CommandReceiptData::Attempt.new(
            change_set_id: command.change_set_id,
            work_item_id: command.work_item_id,
            attempt_id: command.attempt_id
          ),
          warnings:,
          next_actions: [],
          emitted_events: persisted_events.map { event_reference(_1) },
          completed_at: abandoned_at
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def deserialize(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: POLICY_VERSION
        )
      end

      def repository_not_registered(repository_id)
        Failure(
          OutcomeError.new(
            code: :repository_not_registered,
            message: "Repository is not registered",
            details: { repository_id: }
          )
        )
      end
    end
  end
end
