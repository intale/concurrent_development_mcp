# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteExpandWorkIntentionSet < Dry::Operation
      TOOL_NAME = "work_intention_set_expand"

      def initialize(
        event_store:,
        preparer: PrepareExpandWorkIntentionSet.new,
        decider: Domain::WorkIntentions::ExpandSet.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        resource_loader: WorkIntentionResourceLoader.new(event_store:),
        set_loader: WorkIntentionSetLoader.new(event_store:),
        intention_loader: WorkIntentionLoader.new(event_store:),
        boundary_loader: WorkIntentionBoundaryLoader.new(event_store:)
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @repository_registration_loader = repository_registration_loader
        @repository_marker_builder = repository_marker_builder
        @resource_loader = resource_loader
        @set_loader = set_loader
        @intention_loader = intention_loader
        @boundary_loader = boundary_loader
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        prepared = prepare_logical_values(command)
        steps do
          step @event_store.multiple { execute_scoped_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        PreparedWorkIntentionSetExpansion.new(
          expanded_at: @clock.now,
          input_digest: @input_digest.work_intention_set_expand(command),
          resources: command.resources.map do |target|
            PreparedWorkIntentionTargetV1.new(
              target:,
              intention_id: @id_generator.uuid_v7,
              declaration_event_id: @id_generator.uuid_v7,
              membership_event_id: @id_generator.uuid_v7
            )
          end
        )
      end

      def execute_scoped_attempt(command:, prepared:, caused_by:)
        registration = @repository_registration_loader.call(command.repository_id)
        return repository_not_registered(command) unless registration

        resources = load_resources(command)
        return resources if resources.failure?

        requests = resources.value!.zip(prepared.resources).map do |resource, prepared_target|
          RequestedWorkIntentionV1.new(resource:, prepared_target:)
        end
        boundary = load_boundary(command, resources: resources.value!, at: prepared.expanded_at)
        return boundary if boundary.failure?

        set_state = @set_loader.call(command.intention_set_id)
        member_states = set_state.members.map { @intention_loader.call(_1.intention_id).state }
        decision = @decider.call(
          attempt_state: load_attempt_state(command.attempt_id),
          set_state:,
          member_states:,
          boundary: boundary.value!,
          command:,
          requests:,
          expanded_at: prepared.expanded_at
        )
        return decision if decision.failure?

        outcome = decision.value!
        plan = outcome.plan
        persisted = if outcome.write?
                      persist_domain_plan(
                        plan,
                        command:,
                        prepared:,
                        resources: resources.value!,
                        repository_registration: registration,
                        caused_by:
                      )
        else
                      []
        end
        receipt = expansion_receipt(
          plan,
          command:,
          resources: resources.value!,
          prepared:,
          set_state:,
          member_states:
        )
        Success(
          @completion_builder.work_intention_set_expand(
            command:,
            expansion: receipt,
            input_digest: prepared.input_digest,
            persisted_events: persisted,
            completed_at: prepared.expanded_at
          )
        )
      rescue EventHistoryLimitExceeded
        history_limit(command)
      end

      def load_attempt_state(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          EventQueries::ATTEMPT_FOR_WORK_INTENTIONS
        ).map { deserialize(_1) }
        Domain::Attempts::State.reduce(events)
      end

      def load_resources(command)
        resources = command.resources.map do |target|
          result = @resource_loader.call(target, repository_id: command.repository_id)
          return result if result.failure?

          result.value!
        end
        Success(resources)
      end

      def load_boundary(command, resources:, at:)
        markers = resources.flat_map do |resource|
          @repository_marker_builder.work_intention_boundary_markers(
            repository_id: command.repository_id,
            resource_kind: resource.kind,
            resource_path: resource.path
          )
        end.uniq
        @boundary_loader.call(markers, repository_id: command.repository_id, at:)
      end

      def persist_domain_plan(plan, command:, prepared:, resources:, repository_registration:, caused_by:)
        plan.writes.map do |write|
          event = @event_factory.build!(
            event: write.event,
            event_id: event_id_for(write.event, prepared:),
            metadata: command_metadata(command),
            markers: event_markers(command, write.event, resources:, repository_registration:),
            caused_by:
          )
          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def event_id_for(event, prepared:)
        target = prepared.resources.find { _1.intention_id == event.intention_id }
        return target.declaration_event_id if event.is_a?(Events::ResourceWorkIntentionDeclaredV1)

        target.membership_event_id
      end

      def event_markers(command, event, resources:, repository_registration:)
        common = [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "command:#{command.command_id}",
          "work-intention-set:#{event.set_id}",
          *@repository_marker_builder.call(repository_registration)
        ]
        resource = resources.find { _1.resource_id == event.resource_id }
        markers = common + [
          "resource:#{resource.resource_id}",
          "resource-kind:#{resource.kind}",
          "work-intention:#{event.intention_id}"
        ]
        return markers unless event.is_a?(Events::ResourceWorkIntentionDeclaredV1)

        markers + [
          *@repository_marker_builder.work_intention_event_markers(
            repository_id: command.repository_id,
            resource_path: resource.path
          )
        ]
      end

      def expansion_receipt(plan, command:, resources:, prepared:, set_state:, member_states:)
        declarations = plan ? plan.events.grep(Events::ResourceWorkIntentionDeclaredV1) : []
        added = declarations.map do |event|
          resource = resources.find { _1.resource_id == event.resource_id }
          target = prepared.resources.find { _1.intention_id == event.intention_id }.target
          WorkIntentionReceiptReferenceV1.new(
            intention_id: event.intention_id,
            resource_id: event.resource_id,
            resource_kind: resource.kind,
            resource_path: resource.path,
            base_blob_oid: event.base_blob_oid,
            mode: target.mode,
            purpose: target.purpose,
            context: target.context,
            fencing_token: event.fencing_token
          )
        end
        WorkIntentionSetExpansionReceiptV1.new(
          intention_set_id: set_state.set_id,
          repository_id: command.repository_id,
          policy_version: WorkIntentionPolicyV1::VERSION,
          expanded_at: prepared.expanded_at,
          expires_at: member_states.map(&:expires_at).min,
          added_intentions: added,
          intention_count: set_state.members.length + added.length
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
          policy_version: WorkIntentionPolicyV1::VERSION
        )
      end

      def history_limit(command)
        Failure(
          OutcomeError.new(
            code: :resource_boundary_maintenance_required,
            message: "Work-intention boundary history exceeded its decision limit",
            details: {
              repository_id: command.repository_id,
              boundary_marker_count: command.resources.length,
              maximum_delta_event_count: EventQueries::WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT
            }
          )
        )
      end

      def repository_not_registered(command)
        Failure(
          OutcomeError.new(
            code: :repository_not_registered,
            message: "Repository is not registered",
            details: { repository_id: command.repository_id }
          )
        )
      end
    end
  end
end
