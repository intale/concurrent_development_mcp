# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationWaivedV1 < Base
      contract type: "VerificationObligationWaived", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :obligation_event, EventReference
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :previous_status, Types::String.enum("open", "failed")
      attribute :previous_terminal_event, EventReference.optional
      attribute :reason, VerificationObligationWaivers::ReasonV1
      attribute :waiver_input_digest, Types::Sha256Digest
      attribute :waived_at, Types::Timestamp
    end
  end
end
