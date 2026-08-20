# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class OperationGet < QueryTool
        tool_name "operation_get"
        title "Get operation result"
        description "Recover a durable command result and inspect every exact projection barrier."
        input_schema Schemas.operation_get
        query "queries.operation_get"
      end
    end
  end
end
