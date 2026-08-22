# frozen_string_literal: true

module Coordinator::Write
  class PreparedLeaseSetRelease < Value
    Release = Types.Instance(PreparedLeaseReleaseV1)

    attribute :released_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :releases, Types::Array.of(Release).constrained(min_size: 1, max_size: 32)
    attribute :write_set_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
  end
end
