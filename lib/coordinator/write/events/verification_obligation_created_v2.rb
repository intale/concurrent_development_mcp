# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationCreatedV2 < Base
      contract type: "VerificationObligationCreated", version: 2

      attribute :obligation_id, Types::Identifier
      attribute :kind, Types::VerificationObligationKind
      attribute :enforcement, Types::String.enum("verification_gate", "merge_gate")
      attribute :reasons,
                Types::Array.of(Types::CandidateImpactReasonKind)
                  .constrained(min_size: 1, max_size: 3)
      attribute :required_evidence, Types::CandidateImpactRequiredEvidenceKinds
    end
  end
end
