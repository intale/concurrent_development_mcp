# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationEvidenceSubmittedV2 < Base
      contract type: "VerificationEvidenceSubmitted", version: 2

      attribute :evidence_id, Types::UuidV7
      attribute :obligation_id, Types::Identifier
      attribute :evidence_kind, Types::CandidateImpactRequiredEvidenceKind
      attribute :assessment, CompatibilityAssessments::AssessmentV1
      attribute :claim, CompatibilityAssessments::ClaimEvidenceV1
    end
  end
end
