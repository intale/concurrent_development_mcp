# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionGet < QueryTool
        tool_name "decision_get"
        title "Get Decision evidence"
        description "Read the latest available projected Decision evidence without a freshness gate."
        input_schema Schemas.decision_get
        query "queries.decision_get"
      end
    end
  end
end
