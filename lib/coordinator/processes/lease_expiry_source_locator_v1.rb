# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpirySourceLocatorV1 < Value
    attribute :source_event_id, Types::UuidV7
    attribute :resource_key_hash, Types::Sha256Digest
    attribute :stream_revision, Types::Integer.constrained(gteq: 0)

    def self.from_source(source)
      new(
        source_event_id: source.reference.event_id,
        resource_key_hash: source.payload.resource_key_hash,
        stream_revision: source.reference.stream_revision
      )
    end
  end
end
