# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationProgressV1 < Value
    attribute :required_evidence_kinds, Types::CandidateImpactRequiredEvidenceKinds
    attribute :passed_evidence_kinds, Types::Array.of(Types::CandidateImpactRequiredEvidenceKind)
      .constrained(max_size: 8)
    attribute :missing_evidence_kinds, Types::Array.of(Types::CandidateImpactRequiredEvidenceKind)
      .constrained(max_size: 8)
    attribute :evidence_count, Types::Integer.constrained(gteq: 0, lteq: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT)
  end
end
