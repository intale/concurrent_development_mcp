# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkItemDependencyDeclare < MutationTool
        tool_name "work_item_dependency_declare"
        title "Declare a WorkItem dependency"
        description "Declare one typed dependency edge inside a planning ChangeSet."
        input_schema Schemas.work_item_dependency_declare
        operation "operations.submit_declare_work_item_dependency_task"
      end
    end
  end
end
