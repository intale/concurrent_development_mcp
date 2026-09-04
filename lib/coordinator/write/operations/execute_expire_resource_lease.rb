# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteExpireResourceLease < Dry::Operation
      TOOL_NAME = "lease_expire_policy"

      def initialize(
        event_store:,
        decider: Domain::WorkIntentions::Expire.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        resource_loader: WorkIntentionResourceLoader.new(event_store:),
        intention_loader: WorkIntentionLoader.new(event_store:)
      )
        @event_store = event_store
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @repository_registration_loader = repository_registration_loader
        @repository_marker_builder = repository_marker_builder
        @resource_loader = resource_loader
        @intention_loader = intention_loader
      end

      def call(command, caused_by:)
        step call_command(command, caused_by:)
      end

      def call_command(command, caused_by: nil)
        prepared = prepare_logical_values(command)
        loaded = @intention_loader.call(command.lease_id)
        decision = @decider.call(
          state: loaded.state,
          command:,
          observed_at: prepared.expired_at
        )
        return decision if decision.failure?

        outcome = decision.value!
        persisted = []
        if outcome.write?
          result = persist_expiration(
            outcome.plan.writes.fetch(0),
            command:,
            state: loaded.state,
            expected_revision: loaded.stream_revision,
            event_id: prepared.expiration_event_id,
            caused_by:
          )
          return result if result.failure?

          persisted << result.value!
        end
        receipt = WorkIntentionExpiryReceiptV1.new(
          resource_id: command.resource_id,
          lease_id: command.lease_id,
          lease_set_id: command.lease_set_id,
          fencing_token: command.fencing_token,
          expires_at: command.expected_expires_at,
          expired_at: prepared.expired_at
        )
        Success(
          @completion_builder.lease_expire_policy(
            command:,
            expiration: receipt,
            input_digest: prepared.input_digest,
            persisted_events: persisted,
            completed_at: prepared.expired_at
          )
        )
      end

      private

      def prepare_logical_values(command)
        PreparedResourceLeaseExpiry.new(
          expired_at: @clock.now,
          input_digest: @input_digest.lease_expire_policy(command),
          expiration_event_id: @id_generator.uuid_v7
        )
      end

      def persist_expiration(write, command:, state:, expected_revision:, event_id:, caused_by:)
        target = ResourceLeaseTargetV1.new(
          resource_id: state.resource_id,
          base_blob_oid: state.base_blob_oid
        )
        resource = @resource_loader.call(target, repository_id: state.repository_id)
        return resource if resource.failure?
        resource = resource.value!
        registration = @repository_registration_loader.call(state.repository_id)
        return repository_not_registered(state.repository_id) unless registration

        physical = @event_factory.build!(
          event: write.event,
          event_id:,
          metadata: command_metadata(command),
          markers: [
            "change-set:#{state.change_set_id}",
            "work-item:#{state.work_item_id}",
            "attempt:#{state.attempt_id}",
            "command:#{command.command_id}",
            "work-intention-set:#{state.set_id}",
            "work-intention:#{state.intention_id}",
            "resource:#{state.resource_id}",
            "resource-kind:#{resource.kind}",
            *@repository_marker_builder.call(registration),
            *@repository_marker_builder.work_intention_event_markers(
              repository_id: state.repository_id,
              resource_path: resource.path
            )
          ],
          caused_by:
        )
        Success(@event_store.append(write.stream, [ physical ], expected_revision:).fetch(0))
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
