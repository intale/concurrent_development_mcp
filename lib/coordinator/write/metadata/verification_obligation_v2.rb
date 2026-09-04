# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class VerificationObligationV2 < EventMetadata
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :rule_version, Types::CandidateCompatibilityObligationRuleVersion
      attribute :validity_input_digest, Types::Sha256Digest
    end
  end
end
