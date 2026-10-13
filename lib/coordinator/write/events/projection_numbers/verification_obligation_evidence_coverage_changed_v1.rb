# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class VerificationObligationEvidenceCoverageChangedV1 < Coordinator::Write::Events::Base
    contract type: "VerificationObligationEvidenceCoverageChanged", version: 1

    attribute :obligation_id, Coordinator::Write::Types::UuidV7
    EvidenceKinds = Coordinator::Write::Types::Array.of(Coordinator::Write::Types::CandidateImpactRequiredEvidenceKind)
      .constrained(max_size: Coordinator::Write::Types::CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS.length)

    attribute :passed_evidence_kinds, EvidenceKinds
    attribute :missing_evidence_kinds, EvidenceKinds
  end
end
