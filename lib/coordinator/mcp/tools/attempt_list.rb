# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class AttemptList < QueryTool
        tool_name "attempt_list"
        title "List WorkItem Attempt history"
        description "Page immutable Attempt summaries for one WorkItem from the latest available projection."
        input_schema Schemas.attempt_list
        query "queries.attempt_list"
      end
    end
  end
end
