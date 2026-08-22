# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionInterpretationList < QueryTool
        tool_name "decision_interpretation_list"
        title "List interpretation proposals"
        description "Page through available projected atomic proposals for one guidance message."
        input_schema Schemas.decision_interpretation_list
        query "queries.decision_interpretation_list"
      end
    end
  end
end
