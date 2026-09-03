# frozen_string_literal: true

module Coordinator::Write
  class PreparedChangeSetCompletionV1 < Value
    attribute :occurred_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :completion_event_id, Types::UuidV7
  end
end
