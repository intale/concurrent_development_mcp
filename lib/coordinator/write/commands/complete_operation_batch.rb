# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CompleteOperationBatch < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
    end
  end
end
