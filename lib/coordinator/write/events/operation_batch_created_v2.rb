# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCreatedV2 < Base
      contract type: "OperationBatchCreated", version: 2
      Item = OperationBatches::ItemV2

      attribute :batch_id, Types::OperationBatchId
      attribute :target_tool, Types::OperationBatchTargetTool
      attribute :page_size, Types::OperationBatchPageSize
      attribute :items, Types::Array.of(Item).constrained(
        min_size: 1,
        max_size: Types::OPERATION_BATCH_MAXIMUM_ITEMS
      )
    end
  end
end
