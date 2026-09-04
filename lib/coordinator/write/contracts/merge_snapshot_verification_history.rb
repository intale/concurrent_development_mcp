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
          unless history.assignments.empty? && history.submissions.empty? && history.verified.nil?
            key(:history).failure("must not contain verification facts without a snapshot")
          end
          next
        end

        unless coherent_snapshot?(history.snapshot, snapshot_id)
          key(:history).failure("must contain the exact merge snapshot registration")
          next
        end
        unless coherent_submissions?(history, snapshot_id)
          key(:history).failure("must contain coherent bounded verification assignments and submissions")
        end
        key(:history).failure("must contain coherent terminal verification facts") unless coherent_verified?(history, snapshot_id)
      end

      private

      def coherent_snapshot?(snapshot, snapshot_id)
        reference = snapshot.registration_event
        snapshot.merge_snapshot_id == snapshot_id &&
          reference.type == "MergeSnapshotRegistered" &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "MergeSnapshot" &&
          reference.stream_id == snapshot_id &&
          reference.stream_revision.zero?
      end

      def coherent_submissions?(history, snapshot_id)
        return false if history.assignments.length > Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT
        return false unless history.assignments.length == history.submissions.length

        ids = history.assignments.map { _1.assignment.verification_id }
        digests = history.submissions.map(&:verification_input_digest)
        return false unless ids.uniq.length == ids.length && digests.uniq.length == digests.length

        history.assignments.zip(history.submissions).each_with_index.all? do |(assignment_observation, submission_observation), index|
          assignment = assignment_observation.assignment
          assignment_reference = assignment_observation.event
          submission = submission_observation.submission
          submission_reference = submission_observation.event
          assignment.merge_snapshot_id == snapshot_id &&
            submission.merge_snapshot_id == snapshot_id &&
            assignment.verification_id == submission.verification_id &&
            same_snapshot_stream?(assignment_reference, snapshot_id) &&
            assignment_reference.type == "MergeSnapshotVerificationAssigned" &&
            assignment_reference.stream_revision == index + 1 &&
            submission_reference.type == "MergeSnapshotVerificationSubmitted" &&
            submission_reference.stream_context == "DevelopmentIntegration" &&
            submission_reference.stream_name == "MergeVerification" &&
            submission_reference.stream_id == submission.verification_id &&
            submission_reference.stream_revision.zero?
        end
      end

      def coherent_verified?(history, snapshot_id)
        observation = history.verified
        return true unless observation

        selected = observation.selected
        verified = observation.verified
        submission = history.submissions.find { _1.submission.verification_id == selected.verification_id }
        return false unless submission && qualifying?(submission.submission.assessment)

        observation.selected_event.type == "MergeSnapshotVerificationSelected" &&
          same_snapshot_stream?(observation.selected_event, snapshot_id) &&
          observation.selected_event.stream_revision == history.assignments.length + 1 &&
          selected.merge_snapshot_id == snapshot_id &&
          verified.merge_snapshot_id == snapshot_id &&
          observation.verified_event.type == "MergeSnapshotVerified" &&
          same_snapshot_stream?(observation.verified_event, snapshot_id) &&
          observation.verified_event.stream_revision == history.assignments.length + 2 &&
          observation.verified_event.event_id != observation.selected_event.event_id
      end

      def qualifying?(assessment)
        assessment.conclusion == "passed" &&
          assessment.findings.none? { %w[error critical].include?(_1.severity) }
      end

      def same_snapshot_stream?(reference, snapshot_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "MergeSnapshot" &&
          reference.stream_id == snapshot_id
      end
    end
  end
end
