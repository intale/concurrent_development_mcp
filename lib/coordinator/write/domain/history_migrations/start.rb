# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class Start
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Success(new_migration(command)) if state.absent?
          return Success(StartDecisionV1.new(outcome: "existing", plan: nil)) if state.matches?(command)

          Failure(
            OutcomeError.new(
              code: :history_migration_conflict,
              message: "HistoryMigration identity is already bound to different facts",
              details: { migration_id: command.migration_id }
            )
          )
        end

        private

        def new_migration(command)
          stream = @stream_factory.history_migration(command.migration_id)
          events = [
            Events::HistoryMigrationCreatedV1.new(migration_id: command.migration_id),
            Events::HistoryMigrationSourceStoreSelectedV1.new(
              migration_id: command.migration_id,
              source_config_name: command.source_config_name
            ),
            Events::HistoryMigrationTargetStoreSelectedV1.new(
              migration_id: command.migration_id,
              target_config_name: command.target_config_name
            ),
            Events::HistoryMigrationSourceRangeFrozenV1.new(
              migration_id: command.migration_id,
              source_upper_position: command.source_upper_position
            ),
            Events::HistoryMigrationPageSizeSelectedV1.new(
              migration_id: command.migration_id,
              page_size: command.page_size
            ),
            Events::HistoryMigrationStartedV1.new(migration_id: command.migration_id)
          ]

          StartDecisionV1.new(
            outcome: "started",
            plan: EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) })
          )
        end
      end
    end
  end
end
