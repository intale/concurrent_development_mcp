# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RequestOperationBatchContinuation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :page_start, Types::OperationBatchItemIndex
      attribute :page_end, Types::OperationBatchItemIndex
    end
  end
end
