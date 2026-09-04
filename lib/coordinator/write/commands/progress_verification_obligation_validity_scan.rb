# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ProgressVerificationObligationValidityScan < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :scan_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :superseding_partition_event, EventReference
      attribute :expected_checkpoint, EventReference
      attribute :previous_from_position, Types::GlobalPosition
      attribute :last_processed_position, Types::GlobalPosition.optional
      attribute :page_obligation_count, Types::VerificationObligationValidityPageCount
      attribute :has_more, Types::Bool
      attribute :page_size, Types::VerificationObligationValidityPageSize
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end
