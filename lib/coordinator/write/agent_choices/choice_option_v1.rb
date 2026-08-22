# frozen_string_literal: true

module Coordinator::Write
  module AgentChoices
    class ChoiceOptionV1 < Value
      attribute :option_id, Types::Identifier
      attribute :summary, Types::String.constrained(min_size: 1, max_size: 500)
    end
  end
end
