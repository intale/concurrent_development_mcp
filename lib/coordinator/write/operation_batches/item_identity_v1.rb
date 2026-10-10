# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ItemIdentityV1 < Value
      attribute :index, Types::OperationBatchItemIndex
      attribute :command_id, Types::CommandId
      attribute :tool_name, Types::OperationBatchTargetTool
      attribute :canonical_input_digest, Types::Sha256Digest
    end
  end
end
