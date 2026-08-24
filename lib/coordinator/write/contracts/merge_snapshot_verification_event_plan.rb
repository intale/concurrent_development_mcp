# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeSnapshotVerificationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:history).value(Types.Instance(Domain::MergeSnapshotVerifications::HistoryV1))
        required(:command).value(Types.Instance(Commands::SubmitMergeSnapshotVerification))
        required(:snapshot_evidence).value(Types.Instance(MergeSnapshotVerifications::SnapshotEvidenceV1))
        required(:verification_id).filled(:string)
        required(:verification_input_digest).filled(:string)
        required(:submission_event).value(Types.Instance(EventReference))
        required(:submitted_at).filled(:string)
      end

      rule(
        :plan,
        :history,
        :command,
        :snapshot_evidence,
        :verification_id,
        :verification_input_digest,
        :submission_event,
        :submitted_at
      ) do
        reference = values[:submission_event]
        unless coherent_future_reference?(values[:history], values[:command], reference)
          key(:submission_event).failure("must identify the next verification fact in the exact snapshot stream")
          next
        end

        decision = Domain::MergeSnapshotVerifications::Submit.new.call(
          history: values[:history],
          command: values[:command],
          snapshot_evidence: values[:snapshot_evidence],
          verification_id: values[:verification_id],
          verification_input_digest: values[:verification_input_digest],
          submission_event: reference,
          submitted_at: values[:submitted_at]
        )
        key(:plan).failure("must preserve the exact merge verification decision") unless decision.success? && decision.value! == values[:plan]
      end

      private

      def coherent_future_reference?(history, command, reference)
        known = [ history.snapshot_event, *history.submissions.map(&:event), history.verified_event ].compact
        reference.type == "MergeSnapshotVerificationSubmitted" &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "MergeSnapshot" &&
          reference.stream_id == command.merge_snapshot_id &&
          reference.stream_revision == known.map(&:stream_revision).max + 1
      end
    end
  end
end
