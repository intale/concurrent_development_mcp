# frozen_string_literal: true

module Coordinator::Read
  class DecisionGetQueryV1 < Value
    attribute :decision_id, Types::Identifier
  end
end
