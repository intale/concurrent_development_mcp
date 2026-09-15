# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationLoader
      START_HISTORY = EventReadCriteria.new(
        event_types: Operations::ExecuteStartHistoryMigration::EVENT_TYPES,
        maximum_count: Operations::ExecuteStartHistoryMigration::EVENT_TYPES.length,
        direction: :asc
      )
      PROGRESS_EVENT_TYPES = %w[
        HistoryMigrationCursorAdvanced
        HistoryMigrationPlanCompleted
        HistoryMigrationApplicationCursorAdvanced
        HistoryMigrationCompleted
      ].freeze
      PROGRESS_HISTORIES = PROGRESS_EVENT_TYPES.to_h do |event_type|
        [ event_type, LatestEventReadCriteria.new(event_types: [ event_type ]) ]
      end.freeze

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

        progress_events = PROGRESS_HISTORIES.values.filter_map do |criteria|
          @event_store.read_latest(stream, criteria)
        end
        progress = progress_events.to_h { [ _1.type, [ _1, load_event(_1) ] ] }
        upper = start_state.source_upper_position
        verify_progress!(progress, migration_id:, upper:)
        checkpoint_event = progress_events.max_by(&:stream_revision) || start_events.last

        MigrationSnapshotV1.new(
          migration_id:,
          source_config_name: start_state.source_config_name,
          target_config_name: start_state.target_config_name,
          source_upper_position: upper,
          page_size: start_state.page_size,
          next_from_position: planning_next_from_position(progress),
          plan_completed: progress.key?("HistoryMigrationPlanCompleted"),
          application_next_from_position: application_next_from_position(progress),
          completed: progress.key?("HistoryMigrationCompleted"),
          checkpoint_event:,
          latest_revision: [ start_events.last.stream_revision, *progress_events.map(&:stream_revision) ].max
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

      def verify_progress!(progress, migration_id:, upper:)
        progress.each_value do |_event, payload|
          unless payload.migration_id == migration_id
            raise InvalidHistoryMigrationHistory, "HistoryMigration progress disagrees on migration_id"
          end
        end

        planning = progress["HistoryMigrationCursorAdvanced"]&.last
        plan_completed = progress["HistoryMigrationPlanCompleted"]
        application = progress["HistoryMigrationApplicationCursorAdvanced"]&.last
        completed = progress["HistoryMigrationCompleted"]

        if plan_completed
          terminal = upper.nil? ? planning.nil? : planning&.next_from_position == upper + 1
          unless terminal && plan_completed.first.stream_revision > (progress["HistoryMigrationCursorAdvanced"]&.first&.stream_revision || -1)
            raise InvalidHistoryMigrationHistory, "HistoryMigration plan completion has no final planning cursor"
          end
        elsif planning && (!upper || planning.next_from_position > upper)
          raise InvalidHistoryMigrationHistory, "HistoryMigration has a terminal planning cursor without completion"
        end

        if application
          unless plan_completed && upper && application.next_from_position <= upper + 1
            raise InvalidHistoryMigrationHistory, "HistoryMigration application cursor is outside its planned range"
          end
        end

        return unless completed
        terminal_application = upper.nil? ? application.nil? : application&.next_from_position == upper + 1
        unless plan_completed && terminal_application &&
            completed.first.stream_revision > plan_completed.first.stream_revision
          raise InvalidHistoryMigrationHistory, "HistoryMigration completion has no complete application"
        end
      end

      def planning_next_from_position(progress)
        progress["HistoryMigrationCursorAdvanced"]&.last&.next_from_position || 0
      end

      def application_next_from_position(progress)
        progress["HistoryMigrationApplicationCursorAdvanced"]&.last&.next_from_position || 0
      end
    end
  end
end
