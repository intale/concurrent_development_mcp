# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class OperationBatchCancel < MutationTool
        tool_name "operation_batch_cancel"
        title "Request cooperative Operation Batch cancellation"
        description "Stop an Operation Batch at an item boundary. Completed items remain committed and cancellation does not undo them."
        input_schema Schemas.operation_batch_cancel
        operation "operations.submit_cancel_operation_batch_task"
      end
    end
  end
end
