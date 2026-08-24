# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationEvidenceSubmittedV1 < Base
      contract type: "VerificationEvidenceSubmitted", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :obligation_event, EventReference
      attribute :evidence_id, Types::UuidV7
      attribute :evidence_kind, Types::CandidateImpactRequiredEvidenceKind
      attribute :claim, CompatibilityAssessments::ClaimEvidenceV1
      attribute :source_candidate, CandidateObligations::CandidateSubjectV1
      attribute :target_candidate, CandidateObligations::CandidateSubjectV1
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :obligation_validity_input_digest, Types::Sha256Digest
      attribute :assessment, CompatibilityAssessments::AssessmentV1
      attribute :assessment_input_digest, Types::Sha256Digest
      attribute :submitted_at, Types::Timestamp
    end
  end
end
