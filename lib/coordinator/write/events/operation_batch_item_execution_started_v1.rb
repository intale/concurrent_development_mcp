# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchItemExecutionStartedV1 < Base
      contract type: "OperationBatchItemExecutionStarted", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
    end
  end
end
