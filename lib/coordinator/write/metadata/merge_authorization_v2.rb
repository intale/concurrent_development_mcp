# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class MergeAuthorizationV2 < EventMetadata
      attribute :decision_digest, Types::Sha256Digest
      attribute :expected_impact_policy, MergeAuthorizations::ExpectedImpactPolicyV1.optional
      attribute :input_digest, Types::Sha256Digest
    end
  end
end
