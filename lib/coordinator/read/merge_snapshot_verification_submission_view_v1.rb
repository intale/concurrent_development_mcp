# frozen_string_literal: true

module Coordinator::Read
  class MergeSnapshotVerificationSubmissionViewV1 < Value
    attribute :verification_id, Types::UuidV7
    attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
    attribute :assessment, Coordinator::Write::MergeSnapshotVerifications::AssessmentV1
    attribute :verification_input_digest, Types::Sha256Digest
    attribute :submitted_at, Types::Timestamp
    attribute :source, MergeSnapshotSourceEvidenceV1
  end
end
