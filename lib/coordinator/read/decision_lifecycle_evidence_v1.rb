# frozen_string_literal: true

module Coordinator::Read
  class DecisionLifecycleEvidenceV1 < Value
    attribute :event, Coordinator::Write::EventReference
    attribute :actor, AttributedActorV1
    attribute :occurred_at, Types::Timestamp
    attribute :persisted_at, Types::Timestamp
    attribute :causation_id, Types::UuidV7.optional
    attribute :correlation_id, Types::UuidV7.optional
  end
end
