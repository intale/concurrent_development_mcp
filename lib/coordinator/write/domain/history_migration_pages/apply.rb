# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class Apply
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Success(new_application(command)) if state.planned?
          return Success(ApplicationDecisionV1.new(outcome: "existing", plan: nil)) if state.applied?

          Failure(
            OutcomeError.new(
              code: :history_migration_page_conflict,
              message: "HistoryMigrationPage cannot record this target outcome",
              details: { page_id: command.page_id }
            )
          )
        end

        private

        def new_application(command)
          stream = @stream_factory.history_migration_page(command.page_id)
          event = Events::HistoryMigrationPageAppliedV1.new(page_id: command.page_id)
          ApplicationDecisionV1.new(
            outcome: "applied",
            plan: EventPlan.new(writes: [ EventWrite.new(stream:, event:) ])
          )
        end
      end
    end
  end
end
