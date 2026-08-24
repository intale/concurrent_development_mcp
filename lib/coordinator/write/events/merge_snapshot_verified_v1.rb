# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotVerifiedV1 < Base
      contract type: "MergeSnapshotVerified", version: 1

      attribute :merge_snapshot_id, Types::Identifier
      attribute :snapshot, MergeSnapshotVerifications::SnapshotEvidenceV1
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
      attribute :selected_verification, MergeSnapshotVerifications::VerificationDecisionReferenceV1
      attribute :verification_digest, Types::Sha256Digest
      attribute :verified_at, Types::Timestamp
    end
  end
end
