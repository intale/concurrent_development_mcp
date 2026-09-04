# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class SatisfyVerificationObligation < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :obligation_id, Types::Identifier
      attribute :triggering_evidence_id, Types::UuidV7
      attribute :selected_evidence_ids, Types::Array.of(Types::UuidV7).constrained(min_size: 1, max_size: 8)
    end
  end
end
