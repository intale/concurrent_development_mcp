# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchContinuationRequestedV2 < Base
      contract type: "OperationBatchContinuationRequested", version: 2

      attribute :batch_id, Types::OperationBatchId
      attribute :page_start, Types::OperationBatchItemIndex
      attribute :page_end, Types::OperationBatchItemIndex
    end
  end
end
