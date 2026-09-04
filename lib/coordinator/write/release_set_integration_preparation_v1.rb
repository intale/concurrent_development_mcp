# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetIntegrationPreparationV1 < Value
    attribute :recorded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(min_size: 1, max_size: 2)
  end
end
