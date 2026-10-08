# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceProgress
      def initialize(source_reader:)
        @source_reader = source_reader
      end

      # Read-only operator reporting. Count selected facts, not gaps in global positions.
      def call(migration)
        return 100.0 if migration.completed?
        return 0.0 unless migration.source_upper_position

        total = 0
        planned = 0
        applied = 0
        from_position = migration.source_from_position
        while from_position <= migration.source_upper_position
          events = @source_reader.page(SourcePageCriteriaV1.new(
            from_position:, to_position: migration.source_upper_position, page_size: 1_000,
            source_command_ids: migration.source_command_ids
          ))
          break if events.empty?

          total += events.length
          planned += events.count { _1.global_position < migration.next_from_position }
          applied += events.count { _1.global_position < migration.application_next_from_position }
          from_position = events.last.global_position + 1
        end
        return 0.0 if total.zero?

        completed = if migration.plan_completed?
          total * (1 + migration.application_dependency_wave) + applied
        else
          planned
        end
        phases = 2 + Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM
        100.0 * completed / (phases * total)
      end
    end
  end
end
