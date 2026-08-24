# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class WaiveVerificationObligation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :obligation_id, Types::Identifier
      attribute :obligation_validity_input_digest, Types::Sha256Digest
      attribute :reason, VerificationObligationWaivers::ReasonV1
    end
  end
end
