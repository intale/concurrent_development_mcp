# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationSourceTraceResolvedV1 < Base
      contract type: "HistoryMigrationSourceTraceResolved", version: 1

      attribute :trace_id, Types::UuidV7
      attribute :migration_id, Types::UuidV7
      attribute :source_event_id, Types::UuidV7
      attribute :source_global_position, Types::GlobalPosition
      attribute :source_causation_id, Types::UuidV7.optional
      attribute :target_endpoint, EventReference.optional
    end
  end
end
