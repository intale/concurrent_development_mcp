# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordRepositoryIntegration < Dry::Operation
      TOOL_NAME = "release_repository_integration_record"

      def initialize(
        event_store:,
        preparer: PrepareRecordRepositoryIntegration.new,
        history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        snapshot_loader: MergeSnapshots::StateLoader.new(event_store:),
        decider: Domain::ReleaseSets::RecordRepositoryIntegration.new,
        digest_builder: ReleaseSets::IntegrationDigestBuilder.new,
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
        @snapshot_loader = snapshot_loader
        @decider = decider
        @digest_builder = digest_builder
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
        event_count = command.outcome == "integrated" ? 2 : 1
        ReleaseSetIntegrationPreparationV1.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.release_repository_integration_record(command),
          event_ids: event_count.times.map { @id_generator.uuid_v7 }
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @history_loader.call(command.release_set_id)
        observation = load_observation(command.merge_observation_event)
        decision = @decider.call(state:, command:, observation:)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, observation:)
        recorded = plan.events.first
        integration_digest = integration_digest(recorded, state:, command:)
        persisted = persist_plan(
          plan,
          state:,
          command:,
          preparation:,
          integration_digest:,
          caused_by:
        )
        completion = @completion_builder.release_repository_integration_record(
          command:,
          integration: recorded,
          integration_digest:,
          integration_event: persisted.first,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.recorded_at
        )
        Success(completion)
      end

      def load_observation(reference)
        return unless reference

        physical = @event_store.read_at(@stream_factory.merge_snapshot(reference.stream_id), reference.stream_revision)
        return unless physical && physical.type == "MergeObserved" &&
                      physical.metadata.fetch("schema_version") == 2 && event_reference(physical) == reference

        observation = load_event(physical)
        MergeObservations::EvidenceV2.new(
          observation:,
          event: reference,
          observation_digest: physical.metadata.fetch("observation_digest"),
          snapshot: @snapshot_loader.call(observation.merge_snapshot_id)
        )
      end

      def verify_event_plan!(plan, state:, command:, observation:)
        result = @event_plan_contract.call(plan:, state:, command:, observation:)
        return if result.success?

        raise InvalidRepositoryIntegrationEventPlan, result.errors.to_h.inspect
      end

      def integration_digest(integration, state:, command:)
        @digest_builder.call(
          release_set_id: integration.release_set_id,
          release_digest: state.preparation.payload.release_digest,
          repository_id: integration.repository_id,
          member_position: integration.member_position,
          attempt_id: integration.attempt_id,
          attempt_number: integration.attempt_number,
          outcome: integration.outcome,
          merge_observation_event: command.merge_observation_event,
          observation_digest: command.observation_digest,
          failure: integration.failure,
          policy_version: command.policy_version
        )
      end

      def persist_plan(plan, state:, command:, preparation:, integration_digest:, caused_by:)
        parent = caused_by
        plan.writes.zip(preparation.event_ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command:, state:, integration_digest:),
            markers: event_markers(write.event, command),
            caused_by: parent,
            correlation_id: state.preparation.correlation_id
          )
          persisted = @event_store.append(write.stream, [ physical ]).sole
          parent = persisted
          persisted
        end
      end

      def event_metadata(event, command:, state:, integration_digest:)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        }
        return EventMetadata.new(**attributes) unless event.is_a?(Events::RepositoryIntegrationRecordedV2)

        Metadata::RepositoryIntegrationV2.new(
          **attributes,
          integration_digest:,
          observation_digest: command.observation_digest,
          release_digest: state.preparation.payload.release_digest
        )
      end

      def event_markers(event, command)
        markers = [
          "release-set:#{command.release_set_id}",
          "repository:#{command.repository_id}",
          "release-integration-attempt:#{command.attempt_id}",
          "command:#{command.command_id}"
        ]
        if event.is_a?(Events::RepositoryIntegrationRecordedV2)
          markers << "release-integration-outcome:#{event.outcome}"
        elsif event.is_a?(Events::RepositoryIntegrationMergeLinkedV1)
          markers << "merge-snapshot:#{event.merge_observation.stream_id}"
        end
        markers
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
    end
  end
end
