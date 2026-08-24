# frozen_string_literal: true

module Coordinator::Read
  class MergeSnapshotVerifiedViewV1 < Value
    attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
    attribute :selected_verification,
              Coordinator::Write::MergeSnapshotVerifications::VerificationDecisionReferenceV1
    attribute :verification_digest, Types::Sha256Digest
    attribute :verified_at, Types::Timestamp
    attribute :source, MergeSnapshotSourceEvidenceV1
  end
end
