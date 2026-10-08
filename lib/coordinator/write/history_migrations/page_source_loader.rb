# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageSourceLoader
      def initialize(source_reader:, migration_loader:)
        @source_reader = source_reader
        @migration_loader = migration_loader
      end

      def call(state)
        migration = @migration_loader.call(state.migration_id)
        events = @source_reader.page(
          SourcePageCriteriaV1.new(
            from_position: state.from_position,
            to_position: state.to_position,
            page_size: state.source_event_count,
            source_command_ids: migration.source_command_ids
          )
        )
        valid = events.length == state.source_event_count &&
          events.first&.global_position.to_i >= state.from_position &&
          events.last&.global_position == @source_reader.head_position(
            to_position: state.to_position,
            source_command_ids: migration.source_command_ids,
            source_after_position: migration.source_after_position
          )
        return events if valid

        raise InvalidHistoryMigrationHistory,
              "HistoryMigrationPage #{state.page_id} no longer resolves to its frozen source events"
      end
    end
  end
end
