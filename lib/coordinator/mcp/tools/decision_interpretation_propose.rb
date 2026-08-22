# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionInterpretationPropose < MutationTool
        tool_name "decision_interpretation_propose"
        title "Propose an atomic interpretation"
        description "Record one classifier-attributed atomic interpretation without activating policy."
        input_schema Schemas.decision_interpretation_propose
        operation "operations.submit_propose_decision_interpretation_task"
      end
    end
  end
end
