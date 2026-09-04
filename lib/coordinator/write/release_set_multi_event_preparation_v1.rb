# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetMultiEventPreparationV1 < Value
    attribute :occurred_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :event_ids,
              Types::Array.of(Types::UuidV7)
                .constrained(min_size: 2, max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS + 1)
  end
end
