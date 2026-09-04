# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class VerificationInvalidationV2 < EventMetadata
      attribute :invalidated_policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :invalidation_digest, Types::Sha256Digest
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end
