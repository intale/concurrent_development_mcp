# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WorkIntentionSetRenew < MutationTool
        tool_name "work_intention_set_renew"
        title "Renew a work-intention set"
        description "Request renewal of every active advisory Resource work intention in an Attempt's exact observed set. The Task remains working while the Saga renews members independently. A later failure preserves earlier renewals and completes the Task with a typed error. Inspect per-member progress with work_intention_renewal_get using the returned Task ID as task_id."
        input_schema Schemas.work_intention_set_renew
        operation "operations.submit_renew_work_intention_set_task"
      end
    end
  end
end
