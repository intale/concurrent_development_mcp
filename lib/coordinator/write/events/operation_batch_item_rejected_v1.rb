# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchItemRejectedV1 < Base
      contract type: "OperationBatchItemRejected", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :command_id, Types::Identifier
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :result, Tasks::StructuredContentV1
      attribute :finished_at, Types::Timestamp
    end
  end
end
