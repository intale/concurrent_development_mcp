# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageSourceLoader
      def initialize(source_reader:)
        @source_reader = source_reader
      end

      def call(state)
        events = @source_reader.page(
          SourcePageCriteriaV1.new(
            from_position: state.from_position,
            to_position: state.to_position,
            page_size: state.source_event_count
          )
        )
        valid = events.length == state.source_event_count &&
          events.first&.global_position.to_i >= state.from_position &&
          events.last&.global_position == state.to_position
        return events if valid

        raise InvalidHistoryMigrationHistory,
              "HistoryMigrationPage #{state.page_id} no longer resolves to its frozen source events"
      end
    end
  end
end
