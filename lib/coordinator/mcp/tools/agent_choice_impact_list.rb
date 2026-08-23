# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class AgentChoiceImpactList < QueryTool
        tool_name "agent_choice_impact_list"
        title "List AgentChoice impacts"
        description "Page through available projected Choice impact assessments for one Attempt without a freshness gate."
        input_schema Schemas.agent_choice_impact_list
        query "queries.agent_choice_impact_list"
      end
    end
  end
end
