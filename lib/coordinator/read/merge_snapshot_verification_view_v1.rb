# frozen_string_literal: true

module Coordinator::Read
  class MergeSnapshotVerificationViewV1 < Value
    Submission = MergeSnapshotVerificationSubmissionViewV1

    attribute :status, Types::MergeSnapshotVerificationStatus
    attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
    attribute :submissions,
              Types::Array.of(Submission)
                .constrained(max_size: Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT)
    attribute :verified, MergeSnapshotVerifiedViewV1.optional
  end
end
