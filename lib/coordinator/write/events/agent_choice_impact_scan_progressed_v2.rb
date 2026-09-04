# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanProgressedV2 < Base
      contract type: "AgentChoiceImpactScanProgressed", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :page_number, Types::Integer.constrained(gteq: 1)
      attribute :next_from_position, Types::GlobalPosition
      attribute :decision_change, AgentChoiceImpacts::DecisionChangeEvidenceV2
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::AgentChoiceImpactPageSize
    end
  end
end
