# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionResolve < QueryTool
        tool_name "decision_resolve"
        title "Resolve available Decision context"
        description "Resolve latest available testing-framework policy without treating the projection as write authority."
        input_schema Schemas.decision_resolve
        query "queries.decision_resolve"
      end
    end
  end
end
