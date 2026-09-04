# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationClaimedV2 < Base
      contract type: "VerificationObligationClaimed", version: 2

      attribute :obligation_id, Types::Identifier
      attribute :claim_id, Types::UuidV7
      attribute :claimant_id, Types::Identifier
      attribute :fencing_token, Types::FencingToken
      attribute :expires_at, Types::Timestamp
    end
  end
end
