# frozen_string_literal: true

module Coordinator::Write
  class PreparedDependencySatisfactionV1 < Value
    attribute :occurred_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :satisfaction_event_id, Types::UuidV7
    attribute :readiness_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
  end
end
