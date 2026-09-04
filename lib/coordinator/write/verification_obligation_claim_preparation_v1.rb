# frozen_string_literal: true

module Coordinator::Write
  class VerificationObligationClaimPreparationV1 < Value
    attribute :claim_id, Types::UuidV7
    attribute :claimed_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :claim_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
