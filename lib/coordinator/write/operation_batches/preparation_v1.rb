# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class PreparationV1 < Value
      attribute :input_digest, Types::Sha256Digest
      attribute :domain_event_ids, Types::Array.of(Types::UuidV7)
      attribute :correlation_id, Types::UuidV7
      attribute :items, Types::Array.of(ItemV2)
      attribute :item_encoded_byte_sizes, Types::Array.of(Types::OperationBatchEncodedByteSize)
    end
  end
end
