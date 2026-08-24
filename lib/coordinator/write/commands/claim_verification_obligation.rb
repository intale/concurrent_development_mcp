# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ClaimVerificationObligation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :obligation_id, Types::Identifier
      attribute :claim_duration_seconds, Types::LeaseDurationSeconds
    end
  end
end
