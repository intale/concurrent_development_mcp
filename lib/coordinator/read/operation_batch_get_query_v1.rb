# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchGetQueryV1 < Value
    attribute :batch_id, Types::OperationBatchId
    attribute :after_index, Types::OperationBatchItemIndex.optional
    attribute :limit, Types::Integer.constrained(
      gteq: 1,
      lteq: Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS
    )
  end
end
