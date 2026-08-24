# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class InvalidateVerificationObligation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :obligation_id, Types::Identifier
      attribute :obligation_event, EventReference
      attribute :superseding_partition_event, EventReference
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end
