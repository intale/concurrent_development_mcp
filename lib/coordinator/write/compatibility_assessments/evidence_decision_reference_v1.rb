# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class EvidenceDecisionReferenceV1 < Value
      attribute :evidence_kind, Types::CandidateImpactRequiredEvidenceKind
      attribute :evidence_id, Types::UuidV7
      attribute :conclusion, Types::VerificationEvidenceConclusion
      attribute :result_digest, Types::Sha256Digest
      attribute :assessment_input_digest, Types::Sha256Digest
      attribute :event, EventReference
    end
  end
end
