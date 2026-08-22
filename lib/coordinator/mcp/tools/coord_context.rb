# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CoordContext < QueryTool
        tool_name "coord_context"
        title "Get coordination context"
        description "Load the latest available checkpointed ChangeSet, WorkItem, or Attempt context."
        input_schema Schemas.coord_context
        query "queries.coord_context"
      end
    end
  end
end
