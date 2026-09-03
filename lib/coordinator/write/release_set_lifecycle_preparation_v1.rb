# frozen_string_literal: true

module Coordinator::Write
  class ReleaseSetLifecyclePreparationV1 < Value
    attribute :occurred_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :domain_event_id, Types::UuidV7
  end
end
