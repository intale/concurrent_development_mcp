# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchOutcomeViewV1 < Value
    attribute :index, Types::OperationBatchItemIndex
    attribute :command_id, Types::Identifier
    attribute :canonical_input_digest, Types::Sha256Digest
    attribute :status, Types::OperationBatchOutcomeStatus
    attribute :result, Coordinator::Write::Tasks::StructuredContentV1
    attribute :finished_at, Types::Timestamp
    attribute :source, OperationBatchSourceEvidenceV1
  end
end
