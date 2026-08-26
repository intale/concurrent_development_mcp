# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAbandonAttempt < Dry::Operation
      TOOL_NAME = "attempt_abandon"
      POLICY_VERSION = "attempt-abandonment/v1"

      class PreparedV1 < Value
        attribute :abandoned_at, Types::Timestamp
        attribute :input_digest, Types::Sha256Digest
        attribute :resource_event_ids,
                  Types::Array.of(Types::UuidV7).constrained(min_size: 32, max_size: 32)
        attribute :attempt_event_id, Types::UuidV7
        attribute :work_item_event_id, Types::UuidV7
        attribute :completion_event_id, Types::UuidV7
      end

      class InvalidEventPlan < StandardError; end

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
        compound_marker_builder: CompoundMarkerBuilder.new,
        event_plan_contract: Contracts::AttemptAbandonmentEventPlan.new
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
        @compound_marker_builder = compound_marker_builder
        @event_plan_contract = event_plan_contract
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
        steps do
          prepared = prepare_logical_values(command)

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
          work_item_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        replay = replay_result(command:, input_digest: prepared.input_digest)
        return replay if replay

        attempt_state = load_attempt_state(command.attempt_id)
        current_observations = load_current_observations(attempt_state)
        decision = @decider.call(
          attempt_state:,
          work_item_state: load_work_item_state(command.work_item_id),
          current_observations:,
          command:,
          abandoned_at: prepared.abandoned_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan,
          command:,
          attempt_state:,
          abandoned_at: prepared.abandoned_at
        )
        persisted_events = persist_domain_plan(
          plan,
          command:,
          prepared:,
          caused_by:
        )
        completion = build_completion(
          command:,
          input_digest: prepared.input_digest,
          persisted_events:,
          abandoned_at: prepared.abandoned_at
        )
        persist_completion(
          completion,
          command:,
          event_id: prepared.completion_event_id,
          caused_by:
        )

        Success(completion)
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion

        if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest
          Success(completion)
        else
          Failure(
            OutcomeError.new(
              code: :command_id_reused,
              message: "Command ID is already bound to another tool or input",
              details: {
                command_id: command.command_id,
                existing_tool_name: completion.tool_name,
                existing_input_digest: completion.canonical_input_digest,
                requested_tool_name: TOOL_NAME,
                requested_input_digest: input_digest
              }
            )
          )
        end
      end

      def load_completion(command_id)
        event = @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_COMPLETION
        ).first
        return unless event

        load_event(event)
      end

      def load_attempt_state(attempt_id)
        stream = @stream_factory.attempt(attempt_id)
        membership = @event_store.read(
          stream,
          EventQueries::ATTEMPT_FOR_WRITE_SET_EXPANSION
        )
        latest_lifecycle = @event_store.read_grouped(
          stream,
          GroupedEventReadCriteria.new(
            event_types: [
              "WriteSetRenewed",
              "WriteSetReleased",
              "CandidateAttachedToAttempt",
              "AttemptAbandoned",
              "AttemptCompleted"
            ],
            direction: :desc
          )
        ).reverse

        events = SpecificStreamEventSequence.merge(membership, latest_lifecycle)
        Domain::Attempts::State.reduce(events.map { load_event(_1) })
      end

      def load_work_item_state(work_item_id)
        events = @event_store.read_grouped(
          @stream_factory.work_item(work_item_id),
          GroupedEventReadCriteria.new(
            event_types: [
              "WorkItemCreated",
              "WorkItemMadeReady",
              "WorkItemAcquired",
              "WorkItemRequeued",
              "WorkItemCandidateSelected",
              "WorkItemCompleted"
            ],
            direction: :desc
          )
        ).reverse.map { load_event(_1) }

        Domain::WorkItems::State.reduce(events)
      end

      def load_current_observations(attempt_state)
        attempt_state.lease_resources.map do |reference|
          CurrentLeaseObservationV1.new(
            reference:,
            state: load_lease_state(reference.resource_key_hash)
          )
        end
      end

      def load_lease_state(resource_key_hash)
        events = @event_store.read_grouped(
          @stream_factory.resource_lease(resource_key_hash),
          EventQueries::RESOURCE_LEASE_FOR_RESERVATION
        ).reverse.map { load_event(_1) }

        Domain::ResourceLeases::State.reduce(events)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_event_plan!(plan, command:, attempt_state:, abandoned_at:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          attempt_state:,
          abandoned_at:
        )
        return if result.success?

        raise InvalidEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, command:, prepared:, caused_by:)
        resource_count = plan.writes.length - 2
        event_ids = prepared.resource_event_ids.first(resource_count) + [
          prepared.attempt_event_id,
          prepared.work_item_event_id
        ]

        plan.writes.zip(event_ids).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: command_metadata(command),
            markers: event_markers(command, write.event),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def event_markers(command, event)
        common = [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "command:#{command.command_id}"
        ]
        lease_set_id =
          case event
          when Events::ResourceLeaseReleasedV1, Events::AttemptAbandonedV1
            event.lease_set_id
          end
        common << "lease-set:#{lease_set_id}" if lease_set_id
        return common unless event.is_a?(Events::ResourceLeaseReleasedV1)

        components = [
          "repository:#{event.repository_id}",
          "resource-kind:#{event.resource_kind}",
          "resource-key-hash:#{event.resource_key_hash}"
        ]
        compound = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "resource-identity",
            components:
          )
        )

        common + components + [ compound.marker ]
      end

      def build_completion(command:, input_digest:, persisted_events:, abandoned_at:)
        abandonment = persisted_events[-2]
        released_count = abandonment.data.fetch("released_leases").length
        untouched_count = abandonment.data.fetch("untouched_resource_key_hashes").length
        warnings = [
          "Reacquire the WorkItem with a fresh Attempt ID and base snapshot before resuming."
        ]
        if untouched_count.positive?
          warnings << "#{untouched_count} recorded lease fence(s) were already inactive or superseded and were left untouched."
        end

        Events::CommandCompletedV1.new(
          command_id: command.command_id,
          tool_name: TOOL_NAME,
          canonical_input_digest: input_digest,
          status: "ok",
          summary: "Attempt abandoned; WorkItem requeued; #{released_count} current lease fence(s) released.",
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

      def persist_completion(completion, command:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )

        @event_store.append(@stream_factory.command(command.command_id), [ event ])
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
    end
  end
end
