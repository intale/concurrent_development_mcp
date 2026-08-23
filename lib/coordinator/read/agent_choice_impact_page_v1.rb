# frozen_string_literal: true

module Coordinator::Read
  class AgentChoiceImpactPageV1 < Value
    attribute :attempt_id, Types::Identifier
    attribute :items, Types::Array.of(AgentChoiceImpactViewV1).constrained(max_size: 100)
    attribute :next_global_position, Types::GlobalPosition.optional
    attribute :has_more, Types::Bool
  end
end
