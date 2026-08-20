# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ChangeSetActivate < MutationTool
        tool_name "change_set_activate"
        title "Activate a ChangeSet"
        description "Freeze a valid plan for execution and trigger internal readiness evaluation."
        input_schema Schemas.change_set_activate
        operation "operations.execute_activate_change_set"
      end
    end
  end
end
