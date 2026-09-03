# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetIntegrationPreparationV1 < Value
    attribute :recorded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :integration_event_id, Types::UuidV7
  end
end
