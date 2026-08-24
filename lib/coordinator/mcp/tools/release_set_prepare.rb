# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ReleaseSetPrepare < MutationTool
        tool_name "release_set_prepare"
        title "Prepare an immutable multi-repository release set"
        description "Prepare an ordered ReleaseSet after rechecking every exact authorization in the event store."
        input_schema Schemas.release_set_prepare
        operation "operations.submit_prepare_release_set_task"
      end
    end
  end
end
