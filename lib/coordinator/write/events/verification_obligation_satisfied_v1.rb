# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationSatisfiedV1 < Base
      contract type: "VerificationObligationSatisfied", version: 1

      Evidence = CompatibilityAssessments::EvidenceDecisionReferenceV1

      attribute :obligation_id, Types::Identifier
      attribute :obligation_event, EventReference
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :selected_evidence, Types::Array.of(Evidence).constrained(min_size: 1, max_size: 8)
      attribute :outcome_digest, Types::Sha256Digest
      attribute :satisfied_at, Types::Timestamp
    end
  end
end
