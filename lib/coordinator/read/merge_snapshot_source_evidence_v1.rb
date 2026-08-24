# frozen_string_literal: true

module Coordinator::Read
  class MergeSnapshotSourceEvidenceV1 < Value
    attribute :event, Coordinator::Write::EventReference
    attribute :actor, AttributedActorV1
    attribute :markers, Types::Array.of(Types::Marker).constrained(max_size: 100)
    attribute :metadata, Types::Hash
    attribute :global_position, Types::GlobalPosition
    attribute :occurred_at, Types::Timestamp
    attribute :persisted_at, Types::Timestamp
    attribute :causation_id, Types::UuidV7.optional
    attribute :correlation_id, Types::UuidV7.optional
  end
end
