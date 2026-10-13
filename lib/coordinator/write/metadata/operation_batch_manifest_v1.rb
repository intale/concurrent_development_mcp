# frozen_string_literal: true

module Coordinator::Write::Metadata
  class OperationBatchManifestV1 < Coordinator::Write::EventMetadata
    attribute :item_count, Coordinator::Write::Types::OperationBatchTotal
    attribute :encoded_byte_size, Coordinator::Write::Types::Integer.constrained(gteq: 0)
  end
end
