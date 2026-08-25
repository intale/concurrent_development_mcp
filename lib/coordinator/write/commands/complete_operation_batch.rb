# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CompleteOperationBatch < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :source_event, EventReference
      attribute :completed_at, Types::Timestamp
    end
  end
end
