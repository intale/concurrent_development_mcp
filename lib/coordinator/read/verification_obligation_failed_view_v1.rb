# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationFailedViewV1 < Value
    attribute :obligation_id, Types::Identifier
    attribute :obligation_event, Coordinator::Write::EventReference
    attribute :policy, Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1
    attribute :triggering_evidence, Coordinator::Write::CompatibilityAssessments::EvidenceDecisionReferenceV1
    attribute :outcome_digest, Types::Sha256Digest
    attribute :failed_at, Types::Timestamp
    attribute :evidence, VerificationObligationEvidenceV1
  end
end
