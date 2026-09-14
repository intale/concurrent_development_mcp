# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class OperationBatchItemV1 < EventMetadata
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize
    end
  end
end
