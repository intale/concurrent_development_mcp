# frozen_string_literal: true

module Coordinator::Read
  class MergeAuthorizationViewV1 < Value
    attribute :authorization_id, Types::UuidV7
    attribute :merge_snapshot_id, Types::Identifier
    attribute :outcome, Types::MergeAuthorizationOutcome
    attribute :policy_version, Types::MergeAuthorizationPolicyVersion
    attribute :snapshot_binding, Coordinator::Write::MergeAuthorizations::SnapshotBindingV1
    attribute :expected_impact_policy,
              Coordinator::Write::MergeAuthorizations::ExpectedImpactPolicyV1.optional
    attribute :evaluation, Coordinator::Write::MergeAuthorizations::EvaluationV1
    attribute :input_digest, Types::Sha256Digest
    attribute :decision_digest, Types::Sha256Digest
    attribute :decided_at, Types::Timestamp
    attribute :source, MergeSnapshotSourceEvidenceV1
  end
end
