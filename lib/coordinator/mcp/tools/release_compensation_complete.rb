# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ReleaseCompensationComplete < MutationTool
        tool_name "release_compensation_complete"
        title "Complete ReleaseSet compensation"
        description "Record exact attributed compensation evidence after the ReleaseSet Saga requests it."
        input_schema Schemas.release_compensation_complete
        operation "operations.submit_complete_compensated_release_set_task"
      end
    end
  end
end
