# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRenewLeaseSet < Dry::Operation
      TOOL_NAME = "lease_renew"

      def initialize(
        event_store:,
        preparer: PrepareRenewLeaseSet.new,
        decider: Domain::ResourceLeases::Renew.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        repository_marker_builder: RepositoryMarkerBuilder.new,
        event_plan_contract: Contracts::WriteSetRenewalEventPlan.new
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
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          prepared = prepare_logical_values(command)

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
          write_set_event_id: @id_generator.uuid_v7,
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
          current_observations:,
          command:,
          renewed_at: prepared.renewed_at,
          expires_at: prepared.expires_at
        )
        return decision if decision.failure?

        plan = decision.value!
        renewal = plan.events.last
        repository_registration = @repository_registration_loader.call(renewal.repository_id)
        return repository_not_registered(renewal.repository_id) unless repository_registration

        verify_event_plan!(
          plan,
          command:,
          attempt_state:,
          current_observations:,
          prepared:
        )
        persisted_domain_events = persist_domain_plan(
          plan,
          command:,
          prepared:,
          repository_registration:,
          caused_by:
        )
        completion = @completion_builder.lease_renew(
          command:,
          renewal:,
          input_digest: prepared.input_digest,
          persisted_events: persisted_domain_events,
          completed_at: prepared.renewed_at
        )
        persist_completion(
          completion,
          command:,
          event_id: prepared.completion_event_id,
          policy_version: renewal.policy_version,
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
        lifecycle = @event_store.read_grouped(
          stream,
          EventQueries::ATTEMPT_LATEST_WRITE_SET_LIFECYCLE
        )
        events = SpecificStreamEventSequence.merge(membership, lifecycle.reverse)

        Domain::Attempts::State.reduce(events.map { load_event(_1) })
      end

      def load_current_observations(attempt_state)
        attempt_state.lease_resources.map do |reference|
          CurrentLeaseObservationV2.new(
            reference:,
            state: load_lease_state(reference.resource_id)
          )
        end
      end

      def load_lease_state(resource_id)
        events = @event_store.read_grouped(
          @stream_factory.resource_lease(resource_id),
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

      def verify_event_plan!(plan, command:, attempt_state:, current_observations:, prepared:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          attempt_state:,
          current_observations:,
          renewed_at: prepared.renewed_at,
          expires_at: prepared.expires_at
        )
        return if result.success?

        raise InvalidWriteSetRenewalEventPlan, result.errors.to_h.inspect
      end

      def persist_domain_plan(plan, command:, prepared:, repository_registration:, caused_by:)
        event_ids = prepared.renewals.map(&:event_id) + [ prepared.write_set_event_id ]

        plan.writes.zip(event_ids).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: command_metadata(command, policy_version: write.event.policy_version),
            markers: event_markers(command, write.event, repository_registration:),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def event_markers(command, event, repository_registration:)
        common = [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "command:#{command.command_id}"
        ] + @repository_marker_builder.call(repository_registration) + [ "lease-set:#{event.lease_set_id}" ]
        return common unless event.is_a?(Events::ResourceLeaseRenewedV2)

        common + [
          "resource:#{event.resource_id}",
          "resource-kind:#{event.resource_kind}",
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
