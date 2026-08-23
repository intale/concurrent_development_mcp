# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanStartedV1 < Base
      contract type: "AgentChoiceImpactScanStarted", version: 1

      attribute :scan_id, Types::Identifier
      attribute :decision_change, AgentChoiceImpacts::DecisionChangeEvidenceV1
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::AgentChoiceImpactPageSize
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
      attribute :started_at, Types::Timestamp
    end
  end
end
