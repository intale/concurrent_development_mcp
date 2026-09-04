# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ProgressAgentChoiceImpactScan < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :scan_id, Types::UuidV7
      attribute :expected_checkpoint, EventReference
      attribute :previous_from_position, Types::GlobalPosition
      attribute :last_processed_position, Types::GlobalPosition.optional
      attribute :page_choice_count, Types::AgentChoiceImpactPageChoiceCount
      attribute :has_more, Types::Bool
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
    end
  end
end
