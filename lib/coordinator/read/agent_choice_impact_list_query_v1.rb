# frozen_string_literal: true

module Coordinator::Read
  class AgentChoiceImpactListQueryV1 < Value
    attribute :attempt_id, Types::Identifier
    attribute :after_global_position, Types::GlobalPosition.optional
    attribute :limit, Types::AgentChoiceImpactListLimit
  end
end
