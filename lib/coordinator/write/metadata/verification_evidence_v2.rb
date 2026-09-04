# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class VerificationEvidenceV2 < EventMetadata
      attribute :assessment_input_digest, Types::Sha256Digest
      attribute :obligation_validity_input_digest, Types::Sha256Digest
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
    end
  end
end
