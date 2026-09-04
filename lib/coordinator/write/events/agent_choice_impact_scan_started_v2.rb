# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanStartedV2 < Base
      contract type: "AgentChoiceImpactScanStarted", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :decision_change, AgentChoiceImpacts::DecisionChangeEvidenceV2
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::AgentChoiceImpactPageSize
    end
  end
end
