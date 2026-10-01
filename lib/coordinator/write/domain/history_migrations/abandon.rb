# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class Abandon
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(snapshot:, command:)
          return Success(ProgressDecisionV1.new(outcome: "existing", plan: nil)) if snapshot.abandoned?
          return completed(command) if snapshot.completed?

          stream = @stream_factory.history_migration(command.migration_id)
          event = Events::HistoryMigrationAbandonedV1.new(
            migration_id: command.migration_id,
            reason: command.reason
          )
          Success(
            ProgressDecisionV1.new(
              outcome: "abandoned",
              plan: EventPlan.new(writes: [ EventWrite.new(stream:, event:) ])
            )
          )
        end

        private

        def completed(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_completed,
              message: "Completed HistoryMigration cannot be abandoned",
              details: { migration_id: command.migration_id }
            )
          )
        end
      end
    end
  end
end
