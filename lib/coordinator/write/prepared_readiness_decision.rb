# frozen_string_literal: true

module Coordinator::Write
  class PreparedReadinessDecision < Value
    attribute :occurred_at, Types::Timestamp
    attribute :event_id, Types::UuidV7
  end
end
