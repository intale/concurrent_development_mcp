# frozen_string_literal: true

module Coordinator::Write
  class DevelopmentArtifactClassificationPreparationV1 < Value
    attribute :corrected_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :correction_event_id, Types::UuidV7
  end
end
