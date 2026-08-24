# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationSatisfiedViewV1 < Value
    Evidence = Coordinator::Write::CompatibilityAssessments::EvidenceDecisionReferenceV1

    attribute :obligation_id, Types::Identifier
    attribute :obligation_event, Coordinator::Write::EventReference
    attribute :policy, Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1
    attribute :selected_evidence, Types::Array.of(Evidence).constrained(min_size: 1, max_size: 8)
    attribute :outcome_digest, Types::Sha256Digest
    attribute :satisfied_at, Types::Timestamp
    attribute :evidence, VerificationObligationEvidenceV1
  end
end
