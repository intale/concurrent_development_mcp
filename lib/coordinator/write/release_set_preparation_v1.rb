# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetPreparationV1 < Value
    attribute :prepared_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(min_size: 4, max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS + 3)
    attribute :correlation_id, Types::UuidV7
  end
end
