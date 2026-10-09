# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkIntentionSetDeclare < MutationTool
        tool_name "work_intention_set_declare"
        title "Declare Resource work intentions"
        description <<~TEXT.squish
          Atomically declare an Attempt's initial advisory Resource work intentions. Shared is the default;
          choose exclusive only after deciding overlapping work must be incompatible. A conflicting request
          fails immediately with blocker purpose and context; the coordinator never queues or preempts work.
        TEXT
        input_schema Schemas.work_intention_set_declare
        operation "operations.submit_declare_work_intention_set_task"
      end
    end
  end
end
