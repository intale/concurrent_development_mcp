# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCompletedV1 < Base
      contract type: "OperationBatchCompleted", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :succeeded, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
      attribute :rejected, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
      attribute :outcome_manifest_digest, Types::Sha256Digest
      attribute :completed_at, Types::Timestamp
    end
  end
end
