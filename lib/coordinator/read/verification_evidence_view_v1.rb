# frozen_string_literal: true

module Coordinator::Read
  class VerificationEvidenceViewV1 < Value
    attribute :obligation_id, Types::Identifier
    attribute :obligation_event, Coordinator::Write::EventReference
    attribute :evidence_id, Types::UuidV7
    attribute :evidence_kind, Types::CandidateImpactRequiredEvidenceKind
    attribute :claim, Coordinator::Write::CompatibilityAssessments::ClaimEvidenceV1
    attribute :source_candidate, Coordinator::Write::CandidateObligations::CandidateSubjectV1
    attribute :target_candidate, Coordinator::Write::CandidateObligations::CandidateSubjectV1
    attribute :policy, Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1
    attribute :obligation_validity_input_digest, Types::Sha256Digest
    attribute :assessment, Coordinator::Write::CompatibilityAssessments::AssessmentV1
    attribute :assessment_input_digest, Types::Sha256Digest
    attribute :submitted_at, Types::Timestamp
    attribute :evidence, VerificationObligationEvidenceV1
  end
end
