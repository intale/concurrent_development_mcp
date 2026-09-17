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
          return incomplete(command) unless application_complete?(snapshot)

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

        def application_complete?(snapshot)
          return false unless snapshot.plan_completed?
          return snapshot.application_next_from_position.zero? if snapshot.source_upper_position.nil?

          snapshot.application_dependency_wave == Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM &&
            snapshot.application_next_from_position > snapshot.source_upper_position
        end

        def incomplete(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_application_incomplete,
              message: "HistoryMigration cannot complete before every planned page is applied",
              details: { migration_id: command.migration_id }
            )
          )
        end
      end
    end
  end
end
