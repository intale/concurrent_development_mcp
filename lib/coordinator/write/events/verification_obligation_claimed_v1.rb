# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationClaimedV1 < Base
      contract type: "VerificationObligationClaimed", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :obligation_event, EventReference
      attribute :claim_id, Types::UuidV7
      attribute :claimant_id, Types::Identifier
      attribute :fencing_token, Types::FencingToken
      attribute :claimed_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
    end
  end
end
