# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanCompletedV1 < Base
      contract type: "AgentChoiceImpactScanCompleted", version: 1

      attribute :scan_id, Types::Identifier
      attribute :started_event, EventReference
      attribute :previous_checkpoint, EventReference
      attribute :previous_from_position, Types::GlobalPosition
      attribute :final_from_position, Types::GlobalPosition
      attribute :page_count, Types::Integer.constrained(gteq: 1)
      attribute :page_choice_count, Types::AgentChoiceImpactPageChoiceCount
      attribute :total_choice_count, Types::Integer.constrained(gteq: 0)
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
      attribute :completed_at, Types::Timestamp
    end
  end
end
