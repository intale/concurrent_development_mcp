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
        digest_builder: ReleaseSets::VerificationDigestBuilder.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::ReleaseSetVerificationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @history_loader = history_loader
        @decider = decider
        @digest_builder = digest_builder
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
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
          event_ids: (command.integration_events.length + 1).times.map { @id_generator.uuid_v7 }
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @history_loader.call(command.release_set_id)
        decision = @decider.call(state:, command:)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:)
        verification = plan.events.first
        verification_digest = @digest_builder.call(
          release_set_id: command.release_set_id,
          release_digest: state.preparation.payload.release_digest,
          attempt_number: verification.attempt_number,
          integration_events: command.integration_events,
          evidence: command.evidence,
          policy_version: command.policy_version
        )
        persisted = persist_plan(
          plan,
          state:,
          command:,
          preparation:,
          verification_digest:,
          caused_by:
        )
        completion = @completion_builder.release_verification_record(
          command:,
          verification:,
          integration_events: command.integration_events,
          verification_digest:,
          verification_event: persisted.first,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.recorded_at
        )
        Success(completion)
      end

      def verify_event_plan!(plan, state:, command:)
        result = @event_plan_contract.call(plan:, state:, command:)
        return if result.success?

        raise InvalidReleaseSetVerificationEventPlan, result.errors.to_h.inspect
      end

      def persist_plan(plan, state:, command:, preparation:, verification_digest:, caused_by:)
        parent = caused_by
        plan.writes.zip(preparation.event_ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, state:, command:, verification_digest:),
            markers: event_markers(write.event, command),
            caused_by: parent,
            correlation_id: state.preparation.correlation_id
          )
          persisted = @event_store.append(write.stream, [ physical ]).sole
          parent = persisted
          persisted
        end
      end

      def event_metadata(event, state:, command:, verification_digest:)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        }
        return EventMetadata.new(**attributes) unless event.is_a?(Events::ReleaseSetVerificationRecordedV2)

        Metadata::ReleaseSetVerificationV2.new(
          **attributes,
          release_digest: state.preparation.payload.release_digest,
          verification_digest:
        )
      end

      def event_markers(event, command)
        markers = [ "release-set:#{command.release_set_id}", "command:#{command.command_id}" ]
        if event.is_a?(Events::ReleaseSetVerificationRecordedV2)
          markers << "release-verification-outcome:#{event.evidence.outcome}"
        else
          markers << "repository-integration-event:#{event.integration_event.event_id}"
        end
        markers
      end
    end
  end
end
