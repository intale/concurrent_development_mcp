# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class ConflictV1 < Value
      Decision = ResolvedDecisionV1

      attribute :decisions, Types::Array.of(Decision).constrained(min_size: 2, max_size: 32)
      attribute :reason, Types::String.enum("tied_most_specific")
    end
  end
end
