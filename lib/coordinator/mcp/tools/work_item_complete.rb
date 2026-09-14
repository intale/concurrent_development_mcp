# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkItemComplete < MutationTool
        tool_name "work_item_complete"
        title "Complete a WorkItem with its final Candidate"
        description "Select one exact final Candidate and atomically complete its active Attempt and WorkItem. " \
                    "The authoritative command requires the work-intention set to be withdrawn or expired."
        input_schema Schemas.work_item_complete
        operation "operations.submit_complete_work_item_task"
      end
    end
  end
end
