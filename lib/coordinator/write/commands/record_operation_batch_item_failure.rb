# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordOperationBatchItemFailure < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :failure, Tasks::ExecutionFailureV1
    end
  end
end
