# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordOperationBatchItemOutcome < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :item_command_id, Types::CommandId
      attribute :outcome, Types::String.enum("succeeded", "rejected")
      attribute :target_event, EventReference
      attribute :rejection, OperationBatches::RejectionV1.optional
    end
  end
end
