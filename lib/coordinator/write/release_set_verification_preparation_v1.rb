# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetVerificationPreparationV1 < Value
    attribute :recorded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :verification_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
  end
end
