# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RegisterOperationBatchItemCommand < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
    end
  end
end
