# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkIntentionSetExpand < MutationTool
        tool_name "work_intention_set_expand"
        title "Expand a work-intention set"
        description <<~TEXT.squish
          Atomically add advisory Resource work intentions to an Attempt's active set without extending its
          deadline. Shared is the default; incompatible overlap fails immediately with blocker context.
        TEXT
        input_schema Schemas.work_intention_set_expand
        operation "operations.submit_expand_work_intention_set_task"
      end
    end
  end
end
