# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationWaivedViewV1 < Value
    attribute :obligation_id, Types::Identifier
    attribute :obligation_event, Coordinator::Write::EventReference
    attribute :policy, Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1
    attribute :previous_status, Types::String.enum("open", "failed")
    attribute :previous_terminal_event, Coordinator::Write::EventReference.optional
    attribute :reason, Coordinator::Write::VerificationObligationWaivers::ReasonV1
    attribute :waiver_input_digest, Types::Sha256Digest
    attribute :waived_at, Types::Timestamp
    attribute :evidence, VerificationObligationEvidenceV1
  end
end
