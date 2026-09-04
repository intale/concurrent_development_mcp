# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class FailVerificationObligation < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :obligation_id, Types::Identifier
      attribute :triggering_evidence_id, Types::UuidV7
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000).optional
    end
  end
end
