# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class DecisionEvidenceV2 < Value
      attribute :decision, Events::MergeAuthorizationGrantedV2
      attribute :event, EventReference
      attribute :decision_digest, Types::Sha256Digest
      attribute :expected_impact_policy, ExpectedImpactPolicyV1.optional
      attribute :policy_version, Types::MergeAuthorizationPolicyVersion
    end
  end
end
