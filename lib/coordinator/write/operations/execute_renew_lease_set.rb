# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRenewLeaseSet < Dry::Operation
      TOOL_NAME = "lease_renew"

      def initialize(
        event_store:,
        preparer: PrepareRenewLeaseSet.new,
        decider: Domain::WorkIntentions::RenewSet.new,
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
        intention_loader: WorkIntentionLoader.new(event_store:)
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
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        prepared = prepare_logical_values(command)
        steps do
          step @event_store.multiple { execute_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        renewed_at = @clock.now
        expires_at = (Time.iso8601(renewed_at) + command.lease_duration_seconds).utc.iso8601(6)
        PreparedLeaseSetRenewal.new(
          renewed_at:,
          expires_at:,
          input_digest: @input_digest.lease_renew(command),
          renewals: command.leases.map do |reference|
            PreparedLeaseRenewalV1.new(reference:, event_id: @id_generator.uuid_v7)
          end,
          write_set_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        attempt_state = load_attempt_state(command.attempt_id)
        set_state = @set_loader.call(command.lease_set_id)
        member_states = set_state.members.map { @intention_loader.call(_1.intention_id).state }
        decision = @decider.call(
          attempt_state:,
          set_state:,
          member_states:,
          command:,
          renewed_at: prepared.renewed_at,
          expires_at: prepared.expires_at
        )
        return decision if decision.failure?

        resources = load_resources(member_states, repository_id: set_state.repository_id)
        return resources if resources.failure?
        registration = @repository_registration_loader.call(set_state.repository_id)
        return repository_not_registered(set_state.repository_id) unless registration

        outcome = decision.value!
        persisted = if outcome.write?
                      persist_domain_plan(
                        outcome.plan,
                        command:,
                        prepared:,
                        member_states:,
                        resources: resources.value!,
                        repository_registration: registration,
                        caused_by:
                      )
                    else
                      []
                    end
        receipt = renewal_receipt(
          set_state:,
          member_states:,
          resources: resources.value!,
          prepared:
        )
        Success(
          @completion_builder.lease_renew(
            command:,
            renewal: receipt,
            input_digest: prepared.input_digest,
            persisted_events: persisted,
            completed_at: prepared.renewed_at
          )
        )
      end

      def load_attempt_state(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          EventQueries::ATTEMPT_FOR_WORK_INTENTIONS
        ).map { deserialize(_1) }
        Domain::Attempts::State.reduce(events)
      end

      def load_resources(states, repository_id:)
        resources = states.map do |state|
          target = ResourceLeaseTargetV1.new(
            resource_id: state.resource_id,
            base_blob_oid: state.base_blob_oid
          )
          result = @resource_loader.call(target, repository_id:)
          return result if result.failure?

          result.value!
        end
        Success(resources)
      end

      def persist_domain_plan(
        plan,
        command:,
        prepared:,
        member_states:,
        resources:,
        repository_registration:,
        caused_by:
      )
        plan.writes.map do |write|
          event = write.event
          state = member_states.find { _1.intention_id == event.intention_id }
          resource = resources.find { _1.resource_id == event.resource_id }
          event_id = prepared.renewals.find { _1.reference.lease_id == event.intention_id }.event_id
          physical = @event_factory.build!(
            event:,
            event_id:,
            metadata: command_metadata(command),
            markers: lifecycle_markers(
              command,
              state:,
              resource:,
              repository_registration:
            ),
            caused_by:
          )
          @event_store.append(write.stream, [ physical ]).fetch(0)
        end
      end

      def lifecycle_markers(command, state:, resource:, repository_registration:)
        [
          "change-set:#{state.change_set_id}",
          "work-item:#{state.work_item_id}",
          "attempt:#{state.attempt_id}",
          "command:#{command.command_id}",
          "work-intention-set:#{state.set_id}",
          "work-intention:#{state.intention_id}",
          "resource:#{state.resource_id}",
          "resource-kind:#{resource.kind}",
          *@repository_marker_builder.call(repository_registration),
          *@repository_marker_builder.work_intention_event_markers(
            repository_id: state.repository_id,
            resource_path: resource.path
          )
        ]
      end

      def renewal_receipt(set_state:, member_states:, resources:, prepared:)
        references = member_states.map do |state|
          resource = resources.find { _1.resource_id == state.resource_id }
          LeaseReferenceV2.new(
            lease_id: state.intention_id,
            resource_id: state.resource_id,
            resource_kind: resource.kind,
            resource_path: resource.path,
            base_blob_oid: state.base_blob_oid,
            fencing_token: state.fencing_token
          )
        end
        WorkIntentionSetRenewalReceiptV1.new(
          lease_set_id: set_state.set_id,
          repository_id: set_state.repository_id,
          policy_version: WorkIntentionPolicyV1::VERSION,
          resources: references,
          resource_count: references.length,
          renewed_at: prepared.renewed_at,
          previous_expires_at: member_states.map(&:expires_at).min,
          expires_at: member_states.map { [ _1.expires_at, prepared.expires_at ].max }.min
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
