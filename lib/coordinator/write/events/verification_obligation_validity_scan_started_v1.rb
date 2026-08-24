# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationValidityScanStartedV1 < Base
      contract type: "VerificationObligationValidityScanStarted", version: 1

      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :superseding_partition_event, EventReference
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::VerificationObligationValidityPageSize
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
      attribute :started_at, Types::Timestamp
    end
  end
end
