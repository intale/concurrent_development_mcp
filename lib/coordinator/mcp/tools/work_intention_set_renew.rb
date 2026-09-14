# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkIntentionSetRenew < MutationTool
        tool_name "work_intention_set_renew"
        title "Renew a work-intention set"
        description "Renew every active advisory Resource work intention in an Attempt's exact observed set."
        input_schema Schemas.work_intention_set_renew
        operation "operations.submit_renew_lease_set_task"
      end
    end
  end
end
