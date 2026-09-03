# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordRepositoryIntegration < Dry::Operation
      TOOL_NAME = "release_repository_integration_record"

      def initialize(
        event_store:,
        preparer: PrepareRecordRepositoryIntegration.new,
        history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        decider: Domain::ReleaseSets::RecordRepositoryIntegration.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::RepositoryIntegrationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @history_loader = history_loader
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        ReleaseSetIntegrationPreparationV1.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.release_repository_integration_record(command),
          integration_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @history_loader.call(command.release_set_id)
        observation = load_observation(command.merge_observation_event)
        decision = @decider.call(
          state:,
          command:,
          observation:,
          recorded_at: preparation.recorded_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan,
          state:,
          command:,
          observation:,
          recorded_at: preparation.recorded_at
        )
        integration = plan.events.sole
        persisted = persist_integration(integration, state:, command:, preparation:, caused_by:)
        completion = @completion_builder.release_repository_integration_record(
          command:,
          integration:,
          input_digest: preparation.input_digest,
          persisted_events: [ persisted ],
          completed_at: preparation.recorded_at
        )
        Success(completion)
      end

      def load_observation(reference)
        return unless reference

        physical = @event_store.read_at(@stream_factory.merge_snapshot(reference.stream_id), reference.stream_revision)
        return unless physical && physical.type == "MergeObserved" && event_reference(physical) == reference

        load_event(physical)
      end

      def verify_event_plan!(plan, state:, command:, observation:, recorded_at:)
        result = @event_plan_contract.call(plan:, state:, command:, observation:, recorded_at:)
        return if result.success?

        raise InvalidRepositoryIntegrationEventPlan, result.errors.to_h.inspect
      end

      def persist_integration(integration, state:, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event: integration,
          event_id: preparation.integration_event_id,
          metadata: command_metadata(command),
          markers: integration_markers(command, integration),
          caused_by:,
          correlation_id: state.preparation.correlation_id
        )
        @event_store.append(@stream_factory.release_set(command.release_set_id), [ physical ]).sole
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
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

      def integration_markers(command, integration)
        markers = [
          "release-set:#{command.release_set_id}",
          "repository:#{command.repository_id}",
          "release-integration-outcome:#{integration.outcome}",
          "release-integration-attempt:#{command.attempt_id}",
          "command:#{command.command_id}"
        ]
        markers << "merge-snapshot:#{command.merge_observation_event.stream_id}" if command.merge_observation_event
        markers
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        )
      end
    end
  end
end
