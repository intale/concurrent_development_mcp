# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchItemViewV1 < Value
    attribute :index, Types::OperationBatchItemIndex
    attribute :target_tool, Types::OperationBatchTargetTool
    attribute :command_id, Types::Identifier
    attribute :canonical_input_digest, Types::Sha256Digest
    attribute :arguments, Types::Hash
    attribute :status, Types::OperationBatchItemStatus
    attribute :result, Coordinator::Write::Tasks::StructuredContentV1.optional
    attribute :finished_at, Types::Timestamp.optional
    attribute :source, OperationBatchSourceEvidenceV1.optional
  end
end
