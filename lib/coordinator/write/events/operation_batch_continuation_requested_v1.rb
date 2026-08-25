# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchContinuationRequestedV1 < Base
      contract type: "OperationBatchContinuationRequested", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :page_start, Types::OperationBatchItemIndex
      attribute :page_end, Types::OperationBatchItemIndex
      attribute :source_event, EventReference
      attribute :requested_at, Types::Timestamp
    end
  end
end
