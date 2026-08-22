# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionCorrect < MutationTool
        tool_name "decision_correct"
        title "Correct an active Decision"
        description "Atomically replace an active Decision definition with a separately accepted correction. " \
                    "Pass the latest decision_get current_head event as expected_head; a stale head returns a conflict."
        input_schema Schemas.decision_correct
        operation "operations.submit_correct_decision_task"
      end
    end
  end
end
