# frozen_string_literal: true

module Coordinator::Write
  class PreparedWorkItemCompletionV1 < Value
    attribute :completed_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :domain_event_ids,
              Types::Array.of(Types::UuidV7)
                .constrained(min_size: 3, max_size: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT + 3)
  end
end
