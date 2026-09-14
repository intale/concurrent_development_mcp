# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchItemEnqueuedV1 < Base
      Input = OperationBatches::ItemV1::Target

      contract type: "OperationBatchItemEnqueued", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :command_id, Types::CommandId
      attribute :input, Input
    end
  end
end
