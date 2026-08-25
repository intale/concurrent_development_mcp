# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class OperationBatchGet < QueryTool
        tool_name "operation_batch_get"
        title "Get available Operation Batch progress"
        description "Return the latest available projected Batch summary and a deterministic page of per-item outcomes. Projection lag never blocks this read."
        input_schema Schemas.operation_batch_get
        query "queries.operation_batch_get"
      end
    end
  end
end
