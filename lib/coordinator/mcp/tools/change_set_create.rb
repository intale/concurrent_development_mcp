# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ChangeSetCreate < MutationTool
        tool_name "change_set_create"
        title "Create a ChangeSet"
        description "Create a multi-repository coordination goal and its acceptance criteria."
        input_schema Schemas.change_set_create
        operation "operations.execute_create_change_set"
      end
    end
  end
end
