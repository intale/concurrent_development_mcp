# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class Complete
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(snapshot:, command:)
          return Success(ProgressDecisionV1.new(outcome: "existing", plan: nil)) if snapshot.completed?
          return nonempty(command) unless snapshot.source_upper_position.nil?

          stream = @stream_factory.history_migration(command.migration_id)
          event = Events::HistoryMigrationCompletedV1.new(migration_id: command.migration_id)
          Success(
            ProgressDecisionV1.new(
              outcome: "completed",
              plan: EventPlan.new(writes: [ EventWrite.new(stream:, event:) ])
            )
          )
        end

        private

        def nonempty(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_page_required,
              message: "HistoryMigration has source events and must advance through a page",
              details: { migration_id: command.migration_id }
            )
          )
        end
      end
    end
  end
end
