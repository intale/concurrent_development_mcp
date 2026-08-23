# frozen_string_literal: true

module Coordinator::Read
  class AgentChoiceGetQueryV1 < Value
    attribute :choice_id, Types::Identifier
  end
end
