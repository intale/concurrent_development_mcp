# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class StartVerificationObligationValidityScan < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :superseding_partition_event, EventReference
      attribute :source_global_position, Types::GlobalPosition
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end
