# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchItemCompletionLinkedV1 < Base
      contract type: "OperationBatchItemCompletionLinked", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :command_id, Types::CommandId
      attribute :completion, EventReference
    end
  end
end
