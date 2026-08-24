# frozen_string_literal: true

module Coordinator::Processes
  module VerificationObligationValidity
    class ScanCheckpointV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, Coordinator::Write::EventReference
      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :superseding_partition_event, Coordinator::Write::EventReference
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::VerificationObligationValidityPageSize
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end
