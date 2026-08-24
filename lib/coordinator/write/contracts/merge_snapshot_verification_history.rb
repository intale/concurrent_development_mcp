# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeSnapshotVerificationHistory < Dry::Validation::Contract
      params do
        required(:history).value(Types.Instance(Domain::MergeSnapshotVerifications::HistoryV1))
        required(:merge_snapshot_id).filled(:string)
      end

      rule(:history, :merge_snapshot_id) do
        history = values[:history]
        snapshot_id = values[:merge_snapshot_id]
        if history.absent?
          unless history.snapshot_event.nil? && history.submissions.empty? && history.verified.nil? && history.verified_event.nil?
            key(:history).failure("must not contain verification history without a snapshot")
          end
          next
        end

        unless coherent_snapshot?(history, snapshot_id)
          key(:history).failure("must contain the exact revision-0 merge snapshot registration")
          next
        end
        key(:history).failure("must contain coherent bounded verification submissions") unless coherent_submissions?(history, snapshot_id)
        key(:history).failure("must contain at most one coherent terminal verification") unless coherent_verified?(history, snapshot_id)
      end

      private

      def coherent_snapshot?(history, snapshot_id)
        snapshot = history.snapshot
        reference = history.snapshot_event
        snapshot.merge_snapshot_id == snapshot_id &&
          reference&.type == "MergeSnapshotRegistered" &&
          reference&.stream_context == "DevelopmentIntegration" &&
          reference&.stream_name == "MergeSnapshot" &&
          reference&.stream_id == snapshot_id &&
          reference&.stream_revision == 0
      end

      def coherent_submissions?(history, snapshot_id)
        return false if history.submissions.length > Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT
        digests = history.submissions.map { _1.submission.verification_input_digest }
        return false unless digests.uniq.length == digests.length

        history.submissions.each_with_index.all? do |observation, index|
          submission = observation.submission
          reference = observation.event
          submission.merge_snapshot_id == snapshot_id &&
            submission.snapshot.snapshot == history.snapshot &&
            submission.snapshot.event == history.snapshot_event &&
            reference.type == "MergeSnapshotVerificationSubmitted" &&
            same_stream?(reference, snapshot_id) &&
            reference.stream_revision == index + 1
        end
      end

      def coherent_verified?(history, snapshot_id)
        verified = history.verified
        reference = history.verified_event
        return reference.nil? unless verified

        selected = verified.selected_verification
        observation = history.submissions.find { _1.event == selected.event }
        verified.merge_snapshot_id == snapshot_id &&
          verified.snapshot.snapshot == history.snapshot &&
          verified.snapshot.event == history.snapshot_event &&
          observation&.submission&.verification_id == selected.verification_id &&
          selected.conclusion == "passed" &&
          reference&.type == "MergeSnapshotVerified" &&
          reference && same_stream?(reference, snapshot_id) &&
          reference.stream_revision == history.submissions.length + 1 &&
          verified.verification_digest == MergeSnapshotVerifications::VerifiedDigestBuilder.new.call(
            merge_snapshot_id: snapshot_id,
            snapshot_digest: history.snapshot.snapshot_digest,
            policy_version: verified.policy_version,
            selected_verification: selected
          )
      end

      def same_stream?(reference, snapshot_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "MergeSnapshot" &&
          reference.stream_id == snapshot_id
      end
    end
  end
end
