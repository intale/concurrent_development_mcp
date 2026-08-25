# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CreateOperationBatch < Value
      Item = Types.Instance(OperationBatches::ItemV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :batch_id, Types::OperationBatchId
      attribute :target_tool, Types::OperationBatchTargetTool
      attribute :items, Types::Array.of(Item).constrained(
        min_size: 1,
        max_size: Types::OPERATION_BATCH_MAXIMUM_ITEMS
      )
      attribute :manifest_digest, Types::Sha256Digest
      attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize
      attribute :page_size, Types::OperationBatchPageSize
    end
  end
end
