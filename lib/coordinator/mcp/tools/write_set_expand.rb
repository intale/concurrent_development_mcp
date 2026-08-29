# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WriteSetExpand < MutationTool
        tool_name "write_set_expand"
        title "Expand a Resource write set"
        description "Atomically add Resource IDs to an Attempt's current write set without renewing its deadline."
        input_schema Schemas.write_set_expand
        operation "operations.submit_expand_write_set_task"
      end
    end
  end
end
