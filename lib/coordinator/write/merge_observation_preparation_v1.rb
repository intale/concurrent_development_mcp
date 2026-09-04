# frozen_string_literal: true

module Coordinator::Write
  class MergeObservationPreparationV1 < Value
    attribute :recorded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :observation_event_id, Types::UuidV7
    attribute :authorization_link_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
