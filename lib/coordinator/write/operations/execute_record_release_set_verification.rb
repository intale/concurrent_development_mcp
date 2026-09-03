# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordReleaseSetVerification < Dry::Operation
      TOOL_NAME = "release_verification_record"

      def initialize(
        event_store:,
        preparer: PrepareRecordReleaseSetVerification.new,
        history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        decider: Domain::ReleaseSets::RecordVerification.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::ReleaseSetVerificationEventPlan.new
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
        ReleaseSetVerificationPreparationV1.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.release_verification_record(command),
          verification_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @history_loader.call(command.release_set_id)
        decision = @decider.call(state:, command:, recorded_at: preparation.recorded_at)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, recorded_at: preparation.recorded_at)
        verification = plan.events.sole
        persisted = persist_verification(verification, state:, command:, preparation:, caused_by:)
        completion = @completion_builder.release_verification_record(
          command:,
          verification:,
          input_digest: preparation.input_digest,
          persisted_events: [ persisted ],
          completed_at: preparation.recorded_at
        )
        Success(completion)
      end

      def verify_event_plan!(plan, state:, command:, recorded_at:)
        result = @event_plan_contract.call(plan:, state:, command:, recorded_at:)
        return if result.success?

        raise InvalidReleaseSetVerificationEventPlan, result.errors.to_h.inspect
      end

      def persist_verification(verification, state:, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event: verification,
          event_id: preparation.verification_event_id,
          metadata: command_metadata(command),
          markers: verification_markers(command, verification),
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

      def verification_markers(command, verification)
        [
          "release-set:#{command.release_set_id}",
          "release-verification-outcome:#{verification.evidence.outcome}",
          "command:#{command.command_id}",
          *command.integration_events.map { "repository-integration-event:#{_1.event_id}" }
        ]
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
