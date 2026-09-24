# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationSourceEventPlanMarker
      PURPOSE = "history-migration-source-event-plan"

      def self.call(migration_id:, source_event_id:)
        Coordinator::Shared::Markers::CodecV2.encode(
          purpose: PURPOSE,
          components: [
            { dimension: "migration-id", value: migration_id },
            { dimension: "source-event", value: source_event_id }
          ]
        )
      end
    end
  end
end
