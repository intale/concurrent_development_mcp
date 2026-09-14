# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkIntentionSetWithdraw < MutationTool
        tool_name "work_intention_set_withdraw"
        title "Withdraw a work-intention set"
        description "Withdraw every active advisory Resource work intention in an Attempt's exact observed set."
        input_schema Schemas.work_intention_set_withdraw
        operation "operations.submit_release_lease_set_task"
      end
    end
  end
end
