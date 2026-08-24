# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotVerificationSubmittedV1 < Base
      contract type: "MergeSnapshotVerificationSubmitted", version: 1

      attribute :merge_snapshot_id, Types::Identifier
      attribute :snapshot, MergeSnapshotVerifications::SnapshotEvidenceV1
      attribute :verification_id, Types::UuidV7
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
      attribute :assessment, MergeSnapshotVerifications::AssessmentV1
      attribute :verification_input_digest, Types::Sha256Digest
      attribute :submitted_at, Types::Timestamp
    end
  end
end
