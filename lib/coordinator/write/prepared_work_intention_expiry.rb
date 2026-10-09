# frozen_string_literal: true

module Coordinator::Write
  class PreparedWorkIntentionExpiry < Value
    attribute :expired_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :expiration_event_id, Types::UuidV7
  end
end
