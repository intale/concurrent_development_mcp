# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordOperationBatchItemOutcome < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :item_command_id, Types::Identifier
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :result, Tasks::ToolResultV1
      attribute :target_completion, EventReference.optional
      attribute :finished_at, Types::Timestamp
    end
  end
end
