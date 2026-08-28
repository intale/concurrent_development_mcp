# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class OperationBatchGet < QueryTool
        tool_name "operation_batch_get"
        title "Get available Operation Batch progress"
        description <<~TEXT.squish
          Return the latest available projected Batch summary and an immutable, deterministic page
          of original normalized item arguments joined to their outcomes. Follow next_after_index
          until has_more is false. After cancellation, select only items with status not_run and
          submit their arguments to the Batch tool named by target_tool plus the _batch suffix,
          using new outer command_id and batch_id values. Reuse each not-run item's command_id so
          a target that committed before interruption is reconciled idempotently. A cancelling
          status and cancellation evidence are available before terminal completion. Projection
          lag never blocks this read.
        TEXT
        input_schema Schemas.operation_batch_get
        query "queries.operation_batch_get"
      end
    end
  end
end
