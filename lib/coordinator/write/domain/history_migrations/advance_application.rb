# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class AdvanceApplication
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(snapshot:, page:, command:)
          return Success(ApplicationProgressDecisionV1.new(outcome: "existing", plan: nil)) if snapshot.completed?
          return plan_required(command) unless snapshot.plan_completed?
          return mismatch(command) unless page_matches?(page, command)

          desired_cursor = page.to_position + 1
          return mismatch(command) unless command.next_from_position == desired_cursor
          if snapshot.application_next_from_position == desired_cursor
            return Success(ApplicationProgressDecisionV1.new(outcome: "existing", plan: nil))
          end
          unless snapshot.application_next_from_position == page.from_position
            return checkpoint_changed(command)
          end

          stream = @stream_factory.history_migration(command.migration_id)
          event = Events::HistoryMigrationApplicationCursorAdvancedV1.new(
            migration_id: command.migration_id,
            next_from_position: command.next_from_position
          )
          Success(
            ApplicationProgressDecisionV1.new(
              outcome: "advanced",
              plan: EventPlan.new(writes: [ EventWrite.new(stream:, event:) ])
            )
          )
        end

        private

        def page_matches?(page, command)
          page.applied? && page.page_id == command.page_id && page.migration_id == command.migration_id
        end

        def plan_required(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_plan_required,
              message: "HistoryMigration cannot apply pages before its complete plan",
              details: { migration_id: command.migration_id }
            )
          )
        end

        def mismatch(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_page_conflict,
              message: "HistoryMigrationPage does not match the application cursor",
              details: { migration_id: command.migration_id, page_id: command.page_id }
            )
          )
        end

        def checkpoint_changed(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_checkpoint_changed,
              message: "HistoryMigration application cursor changed; this page may already be superseded",
              details: { migration_id: command.migration_id, page_id: command.page_id }
            )
          )
        end
      end
    end
  end
end
