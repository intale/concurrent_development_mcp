# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCancelledV1 < Base
      contract type: "OperationBatchCancelled", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :succeeded, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
      attribute :rejected, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
      attribute :not_run, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
      attribute :cancellation_event, EventReference
      attribute :cancelled_at, Types::Timestamp
    end
  end
end
