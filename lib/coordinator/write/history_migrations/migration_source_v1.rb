# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationSourceV1 < Value
      attribute :config_name, Types::Identifier
      attribute :event_id, Types::String.constrained(min_size: 1, max_size: 255)
      attribute :event_type, Types::String.constrained(min_size: 1, max_size: 255)
      attribute :schema_version, Types::Integer.constrained(gteq: 1)
      attribute :stream_context, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :stream_name, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :stream_id, Types::String.constrained(min_size: 1, max_size: 2_048)
      attribute :stream_revision, Types::Integer.constrained(gteq: 0)
      attribute :global_position, Types::GlobalPosition
      attribute :created_at, Types::Timestamp
      attribute :causation_id, Types::String.constrained(min_size: 1, max_size: 255).optional
      attribute :correlation_id, Types::String.constrained(min_size: 1, max_size: 255)
    end
  end
end
