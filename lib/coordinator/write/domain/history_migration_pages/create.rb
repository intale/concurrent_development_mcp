# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class Create
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return invalid_range(command) if command.from_position > command.to_position
          return Success(new_page(command)) if state.absent?
          return Success(CreationDecisionV1.new(outcome: "existing", plan: nil)) if state.matches_creation?(command)

          Failure(
            OutcomeError.new(
              code: :history_migration_page_conflict,
              message: "HistoryMigrationPage identity is already bound to different facts",
              details: { page_id: command.page_id, migration_id: command.migration_id }
            )
          )
        end

        private

        def new_page(command)
          stream = @stream_factory.history_migration_page(command.page_id)
          events = [
            Events::HistoryMigrationPageCreatedV1.new(page_id: command.page_id),
            Events::HistoryMigrationPageAddedToMigrationV1.new(
              page_id: command.page_id,
              migration_id: command.migration_id
            ),
            Events::HistoryMigrationPageSourceRangeSelectedV1.new(
              page_id: command.page_id,
              from_position: command.from_position,
              to_position: command.to_position
            ),
            Events::HistoryMigrationPageSourceEventCountRecordedV1.new(
              page_id: command.page_id,
              source_event_count: command.source_event_count
            )
          ]
          CreationDecisionV1.new(
            outcome: "created",
            plan: EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) })
          )
        end

        def invalid_range(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_page_invalid,
              message: "HistoryMigrationPage source range is inverted",
              details: { page_id: command.page_id }
            )
          )
        end
      end
    end
  end
end
