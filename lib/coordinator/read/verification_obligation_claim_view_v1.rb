# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationClaimViewV1 < Value
    attribute :obligation_id, Types::Identifier
    attribute :obligation_event, Coordinator::Write::EventReference
    attribute :claim_id, Types::UuidV7
    attribute :claimant_id, Types::Identifier
    attribute :fencing_token, Types::FencingToken
    attribute :claimed_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
    attribute :evidence, VerificationObligationEvidenceV1
  end
end
