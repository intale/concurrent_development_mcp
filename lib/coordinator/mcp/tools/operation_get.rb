# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class OperationGet < QueryTool
        tool_name "operation_get"
        title "Get operation result"
        description "Read the latest available projected command receipt without a freshness gate."
        input_schema Schemas.operation_get
        query "queries.operation_get"
      end
    end
  end
end
