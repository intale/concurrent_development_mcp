# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetPreparationV1 < Value
    attribute :prepared_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :prepared_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
