# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteVerifyMergeSnapshot < Dry::Operation
      def initialize(
        event_store:,
        history_loader: MergeSnapshotVerifications::HistoryLoader.new(event_store:),
        decider: Domain::MergeSnapshotVerifications::Verify.new,
        digest_builder: MergeSnapshotVerifications::VerifiedDigestBuilder.new,
        event_factory: EventFactory.new,
        id_generator: IdGenerator.new,
        event_plan_contract: Contracts::MergeSnapshotVerificationDecisionEventPlan.new
      )
        @event_store = event_store
        @history_loader = history_loader
        @decider = decider
        @digest_builder = digest_builder
        @event_factory = event_factory
        @id_generator = id_generator
        @event_plan_contract = event_plan_contract
      end

      def call(command, caused_by: nil)
        preparation = MergeSnapshotVerificationDecisionPreparationV1.new(
          selected_event_id: @id_generator.uuid_v7,
          verified_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
        @event_store.multiple do
          execute_attempt(command:, caused_by:, preparation:)
        end
      end

      private

      def execute_attempt(command:, caused_by:, preparation:)
        history = @history_loader.call(command.merge_snapshot_id)
        decision = @decider.call(history:, command:)
        return decision if decision.failure?

        plan = decision.value!
        verify_plan!(plan, history:, command:)
        return Success(nil) unless plan

        submission = history.submissions.find do |observation|
          observation.submission.verification_id == command.verification_id
        end
        selected_verification = MergeSnapshotVerifications::VerificationDecisionReferenceV1.new(
          verification_id: submission.submission.verification_id,
          evidence_kind: submission.submission.assessment.evidence_kind,
          conclusion: "passed",
          result_digest: submission.submission.assessment.result_digest,
          verification_input_digest: submission.verification_input_digest,
          event: submission.event
        )
        verification_digest = @digest_builder.call(
          merge_snapshot_id: command.merge_snapshot_id,
          snapshot_digest: history.snapshot.snapshot_digest,
          policy_version: command.policy_version,
          selected_verification:
        )
        persist_plan(
          plan,
          command:,
          caused_by:,
          preparation:,
          verification_digest:
        )
        Success(plan)
      end

      def verify_plan!(plan, history:, command:)
        result = @event_plan_contract.call(plan:, history:, command:)
        return if result.success?

        raise InvalidMergeSnapshotVerificationEventPlan, result.errors.to_h.inspect
      end

      def persist_plan(plan, command:, caused_by:, preparation:, verification_digest:)
        ids = [ preparation.selected_event_id, preparation.verified_event_id ]
        parent = caused_by
        correlation_id = caused_by&.correlation_id || preparation.correlation_id
        plan.writes.zip(ids).each do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command, verification_digest),
            markers: event_markers(command, write.event),
            caused_by: parent,
            correlation_id:
          )
          parent = @event_store.append(write.stream, [ physical ]).sole
        end
      end

      def event_metadata(event, command, verification_digest)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        }
        case event
        when Events::MergeSnapshotVerificationSelectedV1
          EventMetadata.new(**attributes)
        when Events::MergeSnapshotVerifiedV2
          Metadata::MergeSnapshotVerifiedV2.new(**attributes, verification_digest:)
        else
          raise "Unexpected merge verification decision event #{event.class.name}"
        end
      end

      def event_markers(command, event)
        markers = [
          "merge-snapshot:#{command.merge_snapshot_id}",
          "merge-snapshot-verification:#{command.verification_id}",
          "merge-snapshot-verification-policy:#{command.policy_version}",
          "command:#{command.command_id}"
        ]
        markers << "merge-snapshot-status:verified" if event.is_a?(Events::MergeSnapshotVerifiedV2)
        markers
      end
    end
  end
end
