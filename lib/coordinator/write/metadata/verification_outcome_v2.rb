# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class VerificationOutcomeV2 < EventMetadata
      attribute :outcome_digest, Types::Sha256Digest
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
    end
  end
end
