# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class OperationBatchCreationV2 < EventMetadata
      attribute :manifest_digest, Types::Sha256Digest
      attribute :page_size, Types::OperationBatchPageSize
    end
  end
end
