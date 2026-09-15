# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class Advance
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(snapshot:, page:, command:)
          return Success(ProgressDecisionV1.new(outcome: "existing", plan: nil)) if snapshot.completed?
          return mismatch(command) unless page_matches?(page, command)

          desired_cursor = page.to_position + 1
          return mismatch(command) unless command.next_from_position == desired_cursor
          if snapshot.next_from_position == desired_cursor
            return Success(ProgressDecisionV1.new(outcome: "existing", plan: nil))
          end
          return checkpoint_changed(command) unless snapshot.next_from_position == page.from_position

          Success(progress(snapshot, command))
        end

        private

        def page_matches?(page, command)
          page.applied? && page.page_id == command.page_id && page.migration_id == command.migration_id
        end

        def progress(snapshot, command)
          stream = @stream_factory.history_migration(command.migration_id)
          events = [
            Events::HistoryMigrationCursorAdvancedV1.new(
              migration_id: command.migration_id,
              next_from_position: command.next_from_position
            )
          ]
          if snapshot.source_upper_position && command.next_from_position > snapshot.source_upper_position
            events << Events::HistoryMigrationCompletedV1.new(migration_id: command.migration_id)
          end
          ProgressDecisionV1.new(
            outcome: events.length == 2 ? "completed" : "advanced",
            plan: EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) })
          )
        end

        def mismatch(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_page_conflict,
              message: "HistoryMigrationPage does not match the requested cursor advance",
              details: { migration_id: command.migration_id, page_id: command.page_id }
            )
          )
        end

        def checkpoint_changed(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_checkpoint_changed,
              message: "HistoryMigration cursor changed; this page may already be superseded",
              details: { migration_id: command.migration_id, page_id: command.page_id }
            )
          )
        end
      end
    end
  end
end
