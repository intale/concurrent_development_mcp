# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionAuthorityV1 < Value
      attribute :actor_id, Types::Identifier
      attribute :role, Types::Identifier
    end
  end
end
