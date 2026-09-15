# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationLoader
      START_HISTORY = EventReadCriteria.new(
        event_types: Operations::ExecuteStartHistoryMigration::EVENT_TYPES,
        maximum_count: Operations::ExecuteStartHistoryMigration::EVENT_TYPES.length,
        direction: :asc
      )
      PROGRESS_HISTORY = LatestEventReadCriteria.new(
        event_types: [ "HistoryMigrationCursorAdvanced", "HistoryMigrationCompleted" ]
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

      def call(migration_id)
        stream = @stream_factory.history_migration(migration_id)
        start_events = @event_store.read(stream, START_HISTORY)
        start_state = Domain::HistoryMigrations::State.reduce(start_events.map { load_event(_1) })
        unless start_state.started?
          raise InvalidHistoryMigrationHistory, "HistoryMigration #{migration_id} has no complete start history"
        end

        progress_event = @event_store.read_latest(stream, PROGRESS_HISTORY)
        progress = load_event(progress_event) if progress_event
        upper = start_state.source_upper_position
        verify_progress!(progress, event: progress_event, stream:, migration_id:, upper:)

        MigrationSnapshotV1.new(
          migration_id:,
          source_config_name: start_state.source_config_name,
          target_config_name: start_state.target_config_name,
          source_upper_position: upper,
          page_size: start_state.page_size,
          next_from_position: next_from_position(progress, upper:),
          completed: progress.is_a?(Events::HistoryMigrationCompletedV1),
          checkpoint_event: progress_event || start_events.last,
          latest_revision: [ start_events.last.stream_revision, progress_event&.stream_revision ].compact.max
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

      def verify_progress!(progress, event:, stream:, migration_id:, upper:)
        return unless progress
        unless progress.migration_id == migration_id
          raise InvalidHistoryMigrationHistory, "HistoryMigration progress disagrees on migration_id"
        end
        if progress.is_a?(Events::HistoryMigrationCursorAdvancedV1)
          unless upper && progress.next_from_position <= upper
            raise InvalidHistoryMigrationHistory, "HistoryMigration has a terminal cursor without completion"
          end
          return
        end
        return if upper.nil?

        predecessor = @event_store.read_at(stream, event.stream_revision - 1)
        cursor = load_event(predecessor) if predecessor
        if cursor.is_a?(Events::HistoryMigrationCursorAdvancedV1) &&
            cursor.migration_id == migration_id && cursor.next_from_position == upper + 1
          return
        end

        raise InvalidHistoryMigrationHistory, "HistoryMigration completion has no final cursor"
      end

      def next_from_position(progress, upper:)
        return progress.next_from_position if progress.is_a?(Events::HistoryMigrationCursorAdvancedV1)
        return upper ? upper + 1 : 0 if progress.is_a?(Events::HistoryMigrationCompletedV1)

        0
      end
    end
  end
end
