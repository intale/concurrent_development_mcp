# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class OperationBatchItemAssignmentV1 < EventMetadata
      attribute :canonical_input_digest, Types::Sha256Digest
    end
  end
end
