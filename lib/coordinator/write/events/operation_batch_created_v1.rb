# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCreatedV1 < Base
      contract type: "OperationBatchCreated", version: 1
      Item = OperationBatches::ItemV1

      attribute :batch_id, Types::OperationBatchId
      attribute :target_tool, Types::OperationBatchTargetTool
      attribute :total, Types::OperationBatchTotal
      attribute :page_size, Types::OperationBatchPageSize
      attribute :items, Types::Array.of(Item).constrained(
        min_size: 1,
        max_size: Types::OPERATION_BATCH_MAXIMUM_ITEMS
      )
      attribute :manifest_digest, Types::Sha256Digest
      attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize
      attribute :requester, OperationBatches::ActorV1
      attribute :created_at, Types::Timestamp
    end
  end
end
