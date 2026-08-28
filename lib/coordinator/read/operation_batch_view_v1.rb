# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchViewV1 < Value
    Item = OperationBatchItemViewV1

    attribute :batch_id, Types::OperationBatchId
    attribute :target_tool, Types::OperationBatchTargetTool
    attribute :status, Types::OperationBatchStatus
    attribute :total, Types::OperationBatchTotal
    attribute :succeeded, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
    attribute :rejected, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
    attribute :pending, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
    attribute :not_run, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
    attribute :manifest_digest, Types::Sha256Digest
    attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize
    attribute :items, Types::Array.of(Item).constrained(
      max_size: Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS
    )
    attribute :next_after_index, Types::OperationBatchItemIndex.optional
    attribute :has_more, Types::Bool
    attribute :created, OperationBatchSourceEvidenceV1
    attribute :cancellation, OperationBatchSourceEvidenceV1.optional
    attribute :terminal, OperationBatchSourceEvidenceV1.optional
  end
end
