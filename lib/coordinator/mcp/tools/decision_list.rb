# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class DecisionList < QueryTool
        tool_name "decision_list"
        title "Discover available Decisions by Repository and topic"
        description <<~TEXT.squish
          List bounded latest-available Decision definitions for one canonical Repository UUIDv7, optionally
          filtering by exact extensible topic and policy status. Each observed Decision has a complete
          decision_get action. The projection may lag and is never write authority.
        TEXT
        input_schema Schemas.decision_list
        query "queries.decision_list"
      end
    end
  end
end
