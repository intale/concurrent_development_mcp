# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionActivate < MutationTool
        tool_name "decision_activate"
        title "Activate an accepted interpretation"
        description "Atomically activate one accepted interpretation as authoritative policy."
        input_schema Schemas.decision_activate
        operation "operations.submit_activate_decision_task"
      end
    end
  end
end
