# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteExpireResourceLease < Dry::Operation
      TOOL_NAME = "lease_expire_policy"

      def initialize(
        event_store:,
        decider: Domain::ResourceLeases::Expire.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        compound_marker_builder: CompoundMarkerBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        event_plan_contract: Contracts::ResourceLeaseExpiryEventPlan.new
      )
        @event_store = event_store
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @compound_marker_builder = compound_marker_builder
        @repository_registration_loader = repository_registration_loader
        @repository_marker_builder = repository_marker_builder
        @event_plan_contract = event_plan_contract
      end

      def call(command, caused_by:)
        step call_command(command, caused_by:)
      end

      def call_command(command, caused_by:)
        steps do
          prepared = prepare_logical_values(command)

          step @event_store.multiple { execute_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        PreparedResourceLeaseExpiry.new(
          expired_at: @clock.now,
          input_digest: @input_digest.lease_expire_policy(command),
          expiration_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        replay = replay_result(command:, input_digest: prepared.input_digest)
        return replay if replay

        state = load_lease_state(command.resource_key_hash)
        decision = @decider.call(
          state:,
          command:,
          expired_at: prepared.expired_at
        )
        return decision if decision.failure?

        plan = decision.value!
        expiration = plan.events.fetch(0)
        repository_registration = @repository_registration_loader.call(expiration.repository_id)
        return repository_not_registered(expiration.repository_id) unless repository_registration

        verify_event_plan!(plan, command:, state:, expired_at: prepared.expired_at)
        persisted_expiration = persist_expiration(
          plan.writes.fetch(0),
          command:,
          event_id: prepared.expiration_event_id,
          repository_registration:,
          caused_by:
        )
        completion = @completion_builder.lease_expire_policy(
          command:,
          expiration:,
          input_digest: prepared.input_digest,
          persisted_events: [ persisted_expiration ],
          completed_at: prepared.expired_at
        )
        persist_completion(
          completion,
          command:,
          event_id: prepared.completion_event_id,
          policy_version: expiration.policy_version,
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

      def verify_event_plan!(plan, command:, state:, expired_at:)
        result = @event_plan_contract.call(plan:, command:, state:, expired_at:)
        return if result.success?

        raise InvalidResourceLeaseExpiryEventPlan, result.errors.to_h.inspect
      end

      def persist_expiration(write, command:, event_id:, repository_registration:, caused_by:)
        event = @event_factory.build!(
          event: write.event,
          event_id:,
          metadata: command_metadata(command, policy_version: write.event.policy_version),
          markers: event_markers(command, write.event, repository_registration:),
          caused_by:
        )

        @event_store.append(write.stream, [ event ]).fetch(0)
      end

      def event_markers(command, event, repository_registration:)
        components = [
          "scope:#{repository_registration.scope}",
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

        [
          "change-set:#{event.change_set_id}",
          "work-item:#{event.work_item_id}",
          "attempt:#{event.attempt_id}",
          "command:#{command.command_id}",
          "lease-set:#{event.lease_set_id}",
          *@repository_marker_builder.call(repository_registration),
          *components,
          compound.marker,
          *@repository_marker_builder.resource_event_markers(
            repository_id: event.repository_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path
          )
        ]
      end

      def persist_completion(completion, command:, event_id:, policy_version:, caused_by:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command, policy_version:),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )

        @event_store.append(@stream_factory.command(command.command_id), [ event ])
      end

      def command_metadata(command, policy_version:)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version:
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
