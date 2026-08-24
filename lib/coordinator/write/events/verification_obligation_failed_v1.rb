# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationFailedV1 < Base
      contract type: "VerificationObligationFailed", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :obligation_event, EventReference
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :triggering_evidence, CompatibilityAssessments::EvidenceDecisionReferenceV1
      attribute :outcome_digest, Types::Sha256Digest
      attribute :failed_at, Types::Timestamp
    end
  end
end
