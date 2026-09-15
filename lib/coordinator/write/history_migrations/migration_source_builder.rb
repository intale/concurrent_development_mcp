# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationSourceBuilder
      def call(config_name:, event:)
        MigrationSourceV1.new(
          config_name:,
          event_id: event.id,
          event_type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          created_at: event.created_at.utc.iso8601(6),
          causation_id: event.causation_id,
          correlation_id: event.correlation_id
        )
      end
    end
  end
end
