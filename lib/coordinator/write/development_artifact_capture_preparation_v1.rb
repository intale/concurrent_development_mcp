# frozen_string_literal: true

module Coordinator::Write
  class DevelopmentArtifactCapturePreparationV1 < Value
    attribute :captured_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :capture_event_id, Types::UuidV7
    attribute :observation_event_id, Types::UuidV7
  end
end
