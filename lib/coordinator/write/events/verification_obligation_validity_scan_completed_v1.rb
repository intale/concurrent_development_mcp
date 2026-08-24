# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationValidityScanCompletedV1 < Base
      contract type: "VerificationObligationValidityScanCompleted", version: 1

      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :superseding_partition_event, EventReference
      attribute :started_event, EventReference
      attribute :previous_checkpoint, EventReference
      attribute :previous_from_position, Types::GlobalPosition
      attribute :final_from_position, Types::GlobalPosition
      attribute :page_size, Types::VerificationObligationValidityPageSize
      attribute :page_count, Types::Integer.constrained(gteq: 1)
      attribute :page_obligation_count, Types::VerificationObligationValidityPageCount
      attribute :total_obligation_count, Types::Integer.constrained(gteq: 0)
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
      attribute :completed_at, Types::Timestamp
    end
  end
end
