# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CompatibilityAssessmentSubmit < MutationTool
        tool_name "compatibility_assessment_submit"
        title "Submit compatibility evidence"
        description "Submit exact attributed evidence under the current fenced verification-obligation claim. The authoritative command may leave the obligation open or emit its immediate satisfied or failed outcome."
        input_schema Schemas.compatibility_assessment_submit
        operation "operations.submit_compatibility_assessment_task"
      end
    end
  end
end
