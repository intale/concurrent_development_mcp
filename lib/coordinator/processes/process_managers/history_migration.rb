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
        page_locator:,
        source_reader:,
        page_planning_dispatcher:,
        page_dispatcher:,
        create_page:,
        plan_page:,
        apply_page:,
        advance_migration:,
        advance_application:,
        complete_plan:,
        complete_migration:,
        process_step_planner:
      )
        @source_builder = source_builder
        @migration_loader = migration_loader
        @page_loader = page_loader
        @page_locator = page_locator
        @source_reader = source_reader
        @page_planning_dispatcher = page_planning_dispatcher
        @page_dispatcher = page_dispatcher
        @create_page = create_page
        @plan_page = plan_page
        @apply_page = apply_page
        @advance_migration = advance_migration
        @advance_application = advance_application
        @complete_plan = complete_plan
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
          plan_page(source)
        when Coordinator::Write::Events::HistoryMigrationPagePlannedV1
          advance_migration(source)
        when Coordinator::Write::Events::HistoryMigrationPlanCompletedV1,
             Coordinator::Write::Events::HistoryMigrationApplicationCursorAdvancedV1
          apply_next_page(source)
        when Coordinator::Write::Events::HistoryMigrationPageDependencyWaveAppliedV1
          advance_application(source)
        end
        nil
      end

      private

      def create_next_page(source)
        migration = @migration_loader.call(source.payload.migration_id)
        return if migration.abandoned?
        return if migration.plan_completed?
        return unless migration.checkpoint_event.id == source.event.id
        return complete_empty_plan(source, migration:) if migration.source_upper_position.nil?
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
        # The final page covers an excluded tail too, so all existing wave cursors
        # can reach the original frozen upper bound without creating an empty page.
        to_position = if events.last.global_position == @source_reader.head_position(to_position: migration.source_upper_position)
          migration.source_upper_position
        else
          events.last.global_position
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
              to_position:,
              source_event_count: events.length
            ),
            caused_by: process_step.event
          )
        )
      end

      def plan_page(source)
        page = @page_loader.call(source.payload.page_id)
        return if page.state.planned? || page.state.applied?
        return unless page.event("HistoryMigrationPageSourceEventCountRecorded")&.id == source.event.id

        migration = @migration_loader.call(page.state.migration_id)
        return if migration.abandoned?
        process_step = plan(
          source_event: source.event,
          step_name: "plan-page",
          subject_kind: "history-migration-page",
          subject_id: page.state.page_id,
          allocate_target_entity: false
        )
        target_event_count = execute!(@page_planning_dispatcher.call(migration:, page: page.state))
        execute!(
          @plan_page.call_command(
            Coordinator::Write::Commands::PlanHistoryMigrationPage.new(
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
        return unless page.state.planned?
        return unless page.event("HistoryMigrationPagePlanned")&.id == source.event.id

        migration = @migration_loader.call(page.state.migration_id)
        return if migration.abandoned?
        return if migration.plan_completed?

        process_step = plan(
          source_event: source.event,
          step_name: "advance-planning-cursor",
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

      def apply_next_page(source)
        migration = @migration_loader.call(source.payload.migration_id)
        return if migration.abandoned?
        return if migration.completed?
        return unless migration.checkpoint_event.id == source.event.id
        unless migration.plan_completed?
          raise HistoryMigrationProcessRejected, "HistoryMigration application started before plan completion"
        end

        return complete_migration(source, migration:) if migration.source_upper_position.nil?
        if migration.application_next_from_position > migration.source_upper_position
          unless migration.application_dependency_wave ==
              Coordinator::Shared::Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM
            raise HistoryMigrationProcessRejected, "HistoryMigration dependency wave ended outside its source range"
          end
          return complete_migration(source, migration:)
        end

        location = execute!(
          @page_locator.call(
            migration_id: migration.migration_id,
            from_position: migration.application_next_from_position
          )
        )
        page = @page_loader.call(location.page_id)
        unless page.state.planned?
          raise HistoryMigrationProcessRejected, "HistoryMigration application located an unplanned page"
        end

        dependency_wave = migration.application_dependency_wave
        process_step = plan(
          source_event: source.event,
          step_name: "apply-page-wave-#{dependency_wave}",
          subject_kind: "history-migration-page",
          subject_id: page.state.page_id,
          allocate_target_entity: false
        )
        target_event_count = execute!(
          @page_dispatcher.call(migration:, page: page.state, dependency_wave:)
        )

        execute!(
          @apply_page.call_command(
            Coordinator::Write::Commands::ApplyHistoryMigrationPage.new(
              command_id: process_step.target_command_id,
              actor: ACTOR,
              page_id: page.state.page_id,
              dependency_wave:,
              target_event_count:
            ),
            caused_by: process_step.event
          )
        )
      end

      def advance_application(source)
        page = @page_loader.call(source.payload.page_id)
        return unless page.state.dependency_wave_applied?(source.payload.dependency_wave)
        return unless page.dependency_wave_event(source.payload.dependency_wave).id == source.event.id

        migration = @migration_loader.call(page.state.migration_id)
        return if migration.abandoned?
        return if migration.completed?

        next_dependency_wave, next_from_position = next_application_progress(
          migration:,
          page: page.state,
          dependency_wave: source.payload.dependency_wave
        )
        process_step = plan(
          source_event: source.event,
          step_name: "advance-application-wave-#{source.payload.dependency_wave}",
          subject_kind: "history-migration-page",
          subject_id: page.state.page_id,
          allocate_target_entity: false
        )
        execute!(
          @advance_application.call_command(
            Coordinator::Write::Commands::AdvanceHistoryMigrationApplication.new(
              command_id: process_step.target_command_id,
              actor: ACTOR,
              migration_id: migration.migration_id,
              page_id: page.state.page_id,
              dependency_wave: source.payload.dependency_wave,
              next_dependency_wave:,
              next_from_position:
            ),
            caused_by: process_step.event
          )
        )
      end

      def next_application_progress(migration:, page:, dependency_wave:)
        next_position = page.to_position + 1
        return [ dependency_wave, next_position ] if next_position <= migration.source_upper_position
        if dependency_wave < Coordinator::Shared::Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM
          return [ dependency_wave + 1, 0 ]
        end

        [ dependency_wave, next_position ]
      end

      def complete_empty_plan(source, migration:)
        process_step = plan(
          source_event: source.event,
          step_name: "complete-empty-plan",
          subject_kind: "history-migration",
          subject_id: migration.migration_id,
          allocate_target_entity: false
        )
        execute!(
          @complete_plan.call_command(
            Coordinator::Write::Commands::CompleteHistoryMigrationPlan.new(
              command_id: process_step.target_command_id,
              actor: ACTOR,
              migration_id: migration.migration_id
            ),
            caused_by: process_step.event
          )
        )
      end

      def complete_migration(source, migration:)
        process_step = plan(
          source_event: source.event,
          step_name: "complete-migration",
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
