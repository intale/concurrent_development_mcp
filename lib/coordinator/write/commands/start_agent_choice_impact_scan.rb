# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class StartAgentChoiceImpactScan < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :scan_id, Types::Identifier
      attribute :source_event, EventReference
      attribute :source_global_position, Types::GlobalPosition
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
    end
  end
end
