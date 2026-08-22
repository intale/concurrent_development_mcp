# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class LeaseRenew < MutationTool
        tool_name "lease_renew"
        title "Renew a complete lease set"
        description "Atomically extend every current lease in an Attempt's observed set without changing IDs or fencing tokens."
        input_schema Schemas.lease_renew
        operation "operations.submit_renew_lease_set_task"
      end
    end
  end
end
