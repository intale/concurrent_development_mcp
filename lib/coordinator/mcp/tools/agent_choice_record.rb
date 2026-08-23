# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class AgentChoiceRecord < MutationTool
        tool_name "agent_choice_record"
        title "Record an authoritative agent choice"
        description "Record one significant testing-framework choice for an active Attempt. " \
                    "Pass the exact decision_context returned by decision_resolve; stale context " \
                    "is rejected without recording the choice."
        input_schema Schemas.agent_choice_record
        operation "operations.submit_record_agent_choice_task"
      end
    end
  end
end
