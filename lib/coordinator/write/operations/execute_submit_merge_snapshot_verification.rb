# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteSubmitMergeSnapshotVerification < Dry::Operation
      TOOL_NAME = "merge_verification_submit"

      def initialize(
        event_store:,
        preparer: PrepareSubmitMergeSnapshotVerification.new,
        decider: Domain::MergeSnapshotVerifications::Submit.new,
        input_digest: CommandInputDigest.new,
        verification_input_digest: MergeSnapshotVerifications::VerificationInputDigest.new,
        history_loader: MergeSnapshotVerifications::HistoryLoader.new(event_store:),
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::MergeSnapshotVerificationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @verification_input_digest = verification_input_digest
        @history_loader = history_loader
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
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
        MergeSnapshotVerificationPreparationV1.new(
          verification_id: @id_generator.uuid_v7,
          submitted_at: @clock.now,
          input_digest: @input_digest.merge_verification_submit(command),
          submission_event_id: @id_generator.uuid_v7,
          assignment_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        history = @history_loader.call(command.merge_snapshot_id)
        evidence = snapshot_evidence(history)
        verification_digest = evidence ?
          @verification_input_digest.call(
            policy_version: command.policy_version,
            snapshot: evidence,
            assessment: command.assessment
          ) : preparation.input_digest
        decision = @decider.call(
          history:,
          command:,
          snapshot_evidence: evidence,
          verification_id: preparation.verification_id,
          verification_input_digest: verification_digest
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan,
          history:,
          command:,
          snapshot_evidence: evidence,
          preparation:,
          verification_input_digest: verification_digest
        )
        persisted = persist_plan(plan, command:, preparation:, caused_by:, verification_input_digest: verification_digest)
        completion = @completion_builder.merge_verification_submit(
          command:,
          submission: plan.events.fetch(0),
          verification_input_digest: verification_digest,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.submitted_at
        )
        Success(completion)
      end

      def snapshot_evidence(history)
        return unless history.snapshot

        MergeSnapshotVerifications::SnapshotEvidenceV1.new(
          snapshot: history.snapshot,
          event: history.snapshot.registration_event
        )
      end

      def verify_event_plan!(plan, history:, command:, snapshot_evidence:, preparation:, verification_input_digest:)
        result = @event_plan_contract.call(
          plan:,
          history:,
          command:,
          snapshot_evidence:,
          verification_id: preparation.verification_id,
          verification_input_digest:
        )
        return if result.success?

        raise InvalidMergeSnapshotVerificationEventPlan, result.errors.to_h.inspect
      end

      def persist_plan(plan, command:, preparation:, caused_by:, verification_input_digest:)
        ids = [ preparation.submission_event_id, preparation.assignment_event_id ]
        parent = caused_by
        correlation_id = caused_by&.correlation_id || preparation.correlation_id
        plan.writes.zip(ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command, verification_input_digest),
            markers: event_markers(write.event, command, verification_input_digest),
            caused_by: parent,
            correlation_id:
          )
          persisted = @event_store.append(write.stream, [ physical ]).sole
          parent = persisted
          persisted
        end
      end

      def event_metadata(event, command, verification_input_digest)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        }
        case event
        when Events::MergeSnapshotVerificationSubmittedV2
          Metadata::MergeSnapshotVerificationV2.new(**attributes, verification_input_digest:)
        when Events::MergeSnapshotVerificationAssignedV1
          EventMetadata.new(**attributes)
        else
          raise "Unexpected merge verification submission event #{event.class.name}"
        end
      end

      def event_markers(event, command, verification_input_digest)
        common = [
          "merge-snapshot:#{command.merge_snapshot_id}",
          "merge-snapshot-verification:#{event.verification_id}",
          "merge-snapshot-verification-policy:#{command.policy_version}",
          "command:#{command.command_id}"
        ]
        return common unless event.is_a?(Events::MergeSnapshotVerificationSubmittedV2)

        common + [
          "merge-snapshot-verification-input:#{verification_input_digest}",
          "verification-evidence-kind:#{event.assessment.evidence_kind}",
          "verification-evidence-conclusion:#{event.assessment.conclusion}"
        ]
      end
    end
  end
end
