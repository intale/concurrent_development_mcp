# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageLoader
      EVENT_TYPES = [
        "HistoryMigrationPageCreated",
        "HistoryMigrationPageAddedToMigration",
        "HistoryMigrationPageSourceRangeSelected",
        "HistoryMigrationPageSourceEventCountRecorded",
        "HistoryMigrationPageTargetEventCountRecorded",
        "HistoryMigrationPageApplied"
      ].freeze
      HISTORY = EventReadCriteria.new(
        event_types: EVENT_TYPES,
        maximum_count: EVENT_TYPES.length,
        direction: :asc
      )

      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(page_id)
        events = @event_store.read(@stream_factory.history_migration_page(page_id), HISTORY)
        state = Domain::HistoryMigrationPages::State.reduce(events.map { load_event(_1) })
        PageSnapshotV1.new(
          state:,
          physical_events: events,
          latest_revision: events.last&.stream_revision
        )
      end

      private

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
