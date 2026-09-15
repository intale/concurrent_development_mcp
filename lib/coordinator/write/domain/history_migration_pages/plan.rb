# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class Plan
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Success(new_plan(command)) if state.created?
          if state.planned? && state.target_event_count == command.target_event_count
            return Success(PlanningDecisionV1.new(outcome: "existing", plan: nil))
          end

          Failure(
            OutcomeError.new(
              code: :history_migration_page_conflict,
              message: "HistoryMigrationPage cannot record this target plan",
              details: { page_id: command.page_id }
            )
          )
        end

        private

        def new_plan(command)
          stream = @stream_factory.history_migration_page(command.page_id)
          events = [
            Events::HistoryMigrationPageTargetEventCountRecordedV1.new(
              page_id: command.page_id,
              target_event_count: command.target_event_count
            ),
            Events::HistoryMigrationPagePlannedV1.new(page_id: command.page_id)
          ]
          PlanningDecisionV1.new(
            outcome: "planned",
            plan: EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) })
          )
        end
      end
    end
  end
end
