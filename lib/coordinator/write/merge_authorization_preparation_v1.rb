# frozen_string_literal: true

module Coordinator::Write
  class MergeAuthorizationPreparationV1 < Value
    attribute :authorization_id, Types::UuidV7
    attribute :decided_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :decision_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
