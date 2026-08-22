# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionInterpretationAdjudicate < MutationTool
        tool_name "decision_interpretation_adjudicate"
        title "Adjudicate an interpretation proposal"
        description "Accept for later activation, reject, or request clarification without activating policy."
        input_schema Schemas.decision_interpretation_adjudicate
        operation "operations.submit_adjudicate_decision_interpretation_task"
      end
    end
  end
end
