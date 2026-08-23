# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class AgentChoiceGet < QueryTool
        tool_name "agent_choice_get"
        title "Get AgentChoice evidence"
        description "Read the latest observed AgentChoice lifecycle evidence without a freshness gate."
        input_schema Schemas.agent_choice_get
        query "queries.agent_choice_get"
      end
    end
  end
end
