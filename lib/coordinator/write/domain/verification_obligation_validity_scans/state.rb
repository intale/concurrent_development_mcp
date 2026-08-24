# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationValidityScans
      class State < Value
        attribute :status, Types::VerificationObligationValidityScanStatus
        attribute :scan_id, Types::Identifier.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :superseding_partition_event, EventReference.optional
        attribute :started_event, EventReference.optional
        attribute :checkpoint_event, EventReference.optional
        attribute :from_position, Types::GlobalPosition.optional
        attribute :to_position, Types::GlobalPosition.optional
        attribute :page_size, Types::VerificationObligationValidityPageSize.optional
        attribute :page_count, Types::Integer.constrained(gteq: 0)
        attribute :total_obligation_count, Types::Integer.constrained(gteq: 0)
        attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion.optional

        def self.initial
          new(
            status: "absent",
            scan_id: nil,
            change_set_id: nil,
            superseding_partition_event: nil,
            started_event: nil,
            checkpoint_event: nil,
            from_position: nil,
            to_position: nil,
            page_size: nil,
            page_count: 0,
            total_obligation_count: 0,
            rule_version: nil
          )
        end

        def absent? = status == "absent"
        def running? = status == "running"
        def terminal? = status == "completed"
      end
    end
  end
end
