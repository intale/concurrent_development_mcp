# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class StartOperationBatchItem < Value
      attribute :command_id, Types::CommandId
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :item_command_id, Types::CommandId
      attribute :tool_name, Types::OperationBatchTargetTool
      attribute :canonical_input_digest, Types::Sha256Digest
    end
  end
end
