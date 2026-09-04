# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetVerificationPreparationV1 < Value
    attribute :recorded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :event_ids,
              Types::Array.of(Types::UuidV7)
                .constrained(
                  min_size: Types::RELEASE_SET_MINIMUM_MEMBERS + 1,
                  max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS + 1
                )
  end
end
