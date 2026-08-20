# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CoordContext < QueryTool
        tool_name "coord_context"
        title "Get coordination context"
        description "Load a checkpointed ChangeSet, WorkItem, or Attempt context with explicit projection freshness."
        input_schema Schemas.coord_context
        query "queries.coord_context"
      end
    end
  end
end
