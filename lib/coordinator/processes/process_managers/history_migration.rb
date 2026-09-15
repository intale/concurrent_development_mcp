# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class HistoryMigration
      ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration")
      RULE_VERSION = "history-migration-process/v1"
      HANDLED_CODES = %i[history_migration_page_changed history_migration_checkpoint_changed].freeze

      def initialize(
        source_builder:,
        migration_loader:,
        page_loader:,
        source_reader:,
        page_dispatcher:,
        create_page:,
        apply_page:,
        advance_migration:,
        complete_migration:,
        process_step_planner:
      )
        @source_builder = source_builder
        @migration_loader = migration_loader
        @page_loader = page_loader
        @source_reader = source_reader
        @page_dispatcher = page_dispatcher
        @create_page = create_page
        @apply_page = apply_page
        @advance_migration = advance_migration
        @complete_migration = complete_migration
        @process_step_planner = process_step_planner
      end

      def call(event)
        source = @source_builder.call(event)
        case source.payload
        when Coordinator::Write::Events::HistoryMigrationStartedV1,
             Coordinator::Write::Events::HistoryMigrationCursorAdvancedV1
          create_next_page(source)
        when Coordinator::Write::Events::HistoryMigrationPageSourceEventCountRecordedV1
          apply_page(source)
        when Coordinator::Write::Events::HistoryMigrationPageAppliedV1
          advance_migration(source)
        end
        nil
      end

      private

      def create_next_page(source)
        migration = @migration_loader.call(source.payload.migration_id)
        return if migration.completed?
        return unless migration.checkpoint_event.id == source.event.id
        return complete_empty(source, migration:) if migration.source_upper_position.nil?
        if migration.next_from_position > migration.source_upper_position
          raise HistoryMigrationProcessRejected, "HistoryMigration cursor exceeded its source upper bound"
        end

        events = @source_reader.page(
          Coordinator::Write::HistoryMigrations::SourcePageCriteriaV1.new(
            from_position: migration.next_from_position,
            to_position: migration.source_upper_position,
            page_size: migration.page_size
          )
        )
        if events.empty?
          raise HistoryMigrationProcessRejected, "HistoryMigration source page unexpectedly resolved no events"
        end

        process_step = plan(
          source_event: source.event,
          step_name: "create-page",
          subject_kind: "history-migration-cursor",
          subject_id: "#{migration.migration_id}:#{migration.next_from_position}",
          allocate_target_entity: true
        )
        execute!(
          @create_page.call_command(
            Coordinator::Write::Commands::CreateHistoryMigrationPage.new(
              command_id: process_step.target_command_id,
              actor: ACTOR,
              migration_id: migration.migration_id,
              page_id: process_step.target_entity_id!,
              from_position: migration.next_from_position,
              to_position: events.last.global_position,
              source_event_count: events.length
            ),
            caused_by: process_step.event
          )
        )
      end

      def apply_page(source)
        page = @page_loader.call(source.payload.page_id)
        return if page.state.applied?
        return unless page.event("HistoryMigrationPageSourceEventCountRecorded")&.id == source.event.id

        migration = @migration_loader.call(page.state.migration_id)
        process_step = plan(
          source_event: source.event,
          step_name: "apply-page",
          subject_kind: "history-migration-page",
          subject_id: page.state.page_id,
          allocate_target_entity: false
        )
        target_event_count = execute!(@page_dispatcher.call(migration:, page: page.state))
        execute!(
          @apply_page.call_command(
            Coordinator::Write::Commands::ApplyHistoryMigrationPage.new(
              command_id: process_step.target_command_id,
              actor: ACTOR,
              page_id: page.state.page_id,
              target_event_count:
            ),
            caused_by: process_step.event
          )
        )
      end

      def advance_migration(source)
        page = @page_loader.call(source.payload.page_id)
        return unless page.state.applied?
        return unless page.event("HistoryMigrationPageApplied")&.id == source.event.id

        migration = @migration_loader.call(page.state.migration_id)
        return if migration.completed?

        process_step = plan(
          source_event: source.event,
          step_name: "advance-cursor",
          subject_kind: "history-migration-page",
          subject_id: page.state.page_id,
          allocate_target_entity: false
        )
        execute!(
          @advance_migration.call_command(
            Coordinator::Write::Commands::AdvanceHistoryMigration.new(
              command_id: process_step.target_command_id,
              actor: ACTOR,
              migration_id: migration.migration_id,
              page_id: page.state.page_id,
              next_from_position: page.state.to_position + 1
            ),
            caused_by: process_step.event
          )
        )
      end

      def complete_empty(source, migration:)
        process_step = plan(
          source_event: source.event,
          step_name: "complete-empty-migration",
          subject_kind: "history-migration",
          subject_id: migration.migration_id,
          allocate_target_entity: false
        )
        execute!(
          @complete_migration.call_command(
            Coordinator::Write::Commands::CompleteHistoryMigration.new(
              command_id: process_step.target_command_id,
              actor: ACTOR,
              migration_id: migration.migration_id
            ),
            caused_by: process_step.event
          )
        )
      end

      def plan(source_event:, step_name:, subject_kind:, subject_id:, allocate_target_entity:)
        @process_step_planner.call(
          source_event:,
          process_name: "history-migration",
          step_name:,
          subject_kind:,
          subject_id:,
          rule_version: RULE_VERSION,
          allocate_target_entity:
        )
      end

      def execute!(result)
        return result.value! if result.success?
        return if HANDLED_CODES.include?(result.failure.code)

        failure = result.failure
        raise HistoryMigrationProcessRejected,
              "HistoryMigration process rejected: #{failure.code} - #{failure.message}"
      end
    end
  end
end
