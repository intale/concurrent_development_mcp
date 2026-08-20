# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkItemAcquire < MutationTool
        tool_name "work_item_acquire"
        title "Acquire a WorkItem"
        description "Atomically acquire one ready WorkItem and start an Attempt at exact repository bases."
        input_schema Schemas.work_item_acquire
        operation "operations.execute_acquire_work_item"
      end
    end
  end
end
