# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchItemCommandAssignedV1 < Base
      contract type: "OperationBatchItemCommandAssigned", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :command_id, Types::CommandId
    end
  end
end
