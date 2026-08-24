# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class VerifiedDigestDocumentV1 < Value
      attribute :schema, Types::String.enum("merge-snapshot-verified/v1")
      attribute :merge_snapshot_id, Types::Identifier
      attribute :snapshot_digest, Types::Sha256Digest
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
      attribute :selected_verification, VerificationDecisionReferenceV1
    end
  end
end
