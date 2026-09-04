# frozen_string_literal: true

module Coordinator::Write
  class PreparedChangeSetCompletionV1 < Value
    attribute :occurred_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :domain_event_ids, Types::Array.of(Types::UuidV7).constrained(min_size: 1, max_size: 2)
  end
end
