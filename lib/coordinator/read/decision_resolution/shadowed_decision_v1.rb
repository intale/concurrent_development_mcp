# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class ShadowedDecisionV1 < Value
      attribute :decision, ResolvedDecisionV1
      attribute :reason, Types::String.enum("less_specific")
    end
  end
end
