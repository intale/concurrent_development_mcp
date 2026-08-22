# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkItemCreate < MutationTool
        tool_name "work_item_create"
        title "Create a WorkItem"
        description "Add one repository-scoped unit of work to a planning ChangeSet."
        input_schema Schemas.work_item_create
        operation "operations.submit_create_work_item_task"
      end
    end
  end
end
