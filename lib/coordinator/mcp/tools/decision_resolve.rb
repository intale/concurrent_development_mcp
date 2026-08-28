# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionResolve < QueryTool
        tool_name "decision_resolve"
        title "Resolve available Decision context"
        description <<~TEXT.squish
          Resolve latest available policy for a registered single-choice Decision topic without treating the
          projection as write authority. Other registered topics remain discoverable through decision_list and
          return a typed unsupported-strategy result until their distinct merge semantics are modeled.
        TEXT
        input_schema Schemas.decision_resolve
        query "queries.decision_resolve"
      end
    end
  end
end
