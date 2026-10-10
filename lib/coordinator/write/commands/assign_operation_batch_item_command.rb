# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AssignOperationBatchItemCommand < Value
      attribute :command_id, Types::CommandId
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
    end
  end
end
