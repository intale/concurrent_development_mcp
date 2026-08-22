# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class LeaseRelease < MutationTool
        tool_name "lease_release"
        title "Release a complete lease set"
        description "Atomically release every current lease in an Attempt's exact observed set so the resources can be acquired again."
        input_schema Schemas.lease_release
        operation "operations.submit_release_lease_set_task"
      end
    end
  end
end
