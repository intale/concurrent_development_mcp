# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class DecisionDocumentV1 < Value
      SCHEMA = "merge-authorization-decision/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :policy_version, Types::MergeAuthorizationPolicyVersion
      attribute :input_digest, Types::Sha256Digest
      attribute :snapshot_binding, SnapshotBindingV1
      attribute :expected_impact_policy, ExpectedImpactPolicyV1.optional
      attribute :evaluation, EvaluationV1
      attribute :outcome, Types::MergeAuthorizationOutcome
    end
  end
end
