# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoiceImpacts
      class ScanState < Value
        attribute :status, Types::AgentChoiceImpactScanStatus
        attribute :scan_id, Types::Identifier.optional
        attribute :decision_change, Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1.optional
        attribute :started_event, EventReference.optional
        attribute :checkpoint_event, EventReference.optional
        attribute :from_position, Types::GlobalPosition.optional
        attribute :to_position, Types::GlobalPosition.optional
        attribute :page_size, Types::AgentChoiceImpactPageSize.optional
        attribute :page_count, Types::Integer.constrained(gteq: 0)
        attribute :total_choice_count, Types::Integer.constrained(gteq: 0)
        attribute :policy_version, Types::AgentChoiceImpactPolicyVersion.optional
        attribute :skip_reason, Types::AgentChoiceImpactScanSkipReason.optional

        def self.initial
          new(
            status: "absent",
            scan_id: nil,
            decision_change: nil,
            started_event: nil,
            checkpoint_event: nil,
            from_position: nil,
            to_position: nil,
            page_size: nil,
            page_count: 0,
            total_choice_count: 0,
            policy_version: nil,
            skip_reason: nil
          )
        end

        def absent?
          status == "absent"
        end

        def running?
          status == "running"
        end

        def terminal?
          %w[skipped completed].include?(status)
        end
      end
    end
  end
end
