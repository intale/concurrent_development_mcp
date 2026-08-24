# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeAuthorizationGrantedV1 < Base
      contract type: "MergeAuthorizationGranted", version: 1

      attribute :authorization_id, Types::UuidV7
      attribute :merge_snapshot_id, Types::Identifier
      attribute :policy_version, Types::MergeAuthorizationPolicyVersion
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
      attribute :expected_impact_policy, MergeAuthorizations::ExpectedImpactPolicyV1.optional
      attribute :evaluation, MergeAuthorizations::EvaluationV1
      attribute :input_digest, Types::Sha256Digest
      attribute :decision_digest, Types::Sha256Digest
      attribute :decided_at, Types::Timestamp
    end
  end
end
