# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchItemRejectedV2 < Base
      contract type: "OperationBatchItemRejected", version: 2

      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :command_id, Types::CommandId
    end
  end
end
