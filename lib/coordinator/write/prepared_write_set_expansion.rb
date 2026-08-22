# frozen_string_literal: true

module Coordinator::Write
  class PreparedWriteSetExpansion < Value
    Resource = Types.Instance(PreparedLeaseResourceV1)

    attribute :expanded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    attribute :expansion_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
  end
end
