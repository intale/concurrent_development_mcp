# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchSourceEvidenceV1 < Value
    attribute :event, Coordinator::Write::EventReference
    attribute :actor, AttributedActorV1
    attribute :markers, Types::Array.of(Types::Marker)
    attribute :metadata, Types::Hash
    attribute :global_position, Types::Integer
    attribute :occurred_at, Types::Timestamp
    attribute :persisted_at, Types::Timestamp
    attribute :causation_id, Types::String.optional
    attribute :correlation_id, Types::String.optional
  end
end
