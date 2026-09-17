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
          if state.dependency_wave_applied?(command.dependency_wave)
            return existing(command) if state.target_event_count_for(command.dependency_wave) == command.target_event_count

            return conflict(command)
          end
          if state.planned? && state.next_dependency_wave == command.dependency_wave
            return conflict(command) unless valid_target_event_count?(state, command)

            return Success(new_application(command))
          end

          conflict(command)
        end

        private

        def existing(_command)
          Success(ApplicationDecisionV1.new(outcome: "existing", plan: nil))
        end

        def conflict(command)
          Failure(
            OutcomeError.new(
              code: :history_migration_page_conflict,
              message: "HistoryMigrationPage cannot record this target outcome",
              details: { page_id: command.page_id }
            )
          )
        end

        def valid_target_event_count?(state, command)
          applied_count = state.applied_wave_target_event_counts.sum + command.target_event_count
          return false if applied_count > state.target_event_count
          return true unless command.dependency_wave == Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM

          applied_count == state.target_event_count
        end

        def new_application(command)
          stream = @stream_factory.history_migration_page(command.page_id)
          events = [
            Events::HistoryMigrationPageDependencyWaveAppliedV1.new(
              page_id: command.page_id,
              dependency_wave: command.dependency_wave,
              target_event_count: command.target_event_count
            )
          ]
          if command.dependency_wave == Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM
            events << Events::HistoryMigrationPageAppliedV1.new(page_id: command.page_id)
          end
          ApplicationDecisionV1.new(
            outcome: "applied",
            plan: EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) })
          )
        end
      end
    end
  end
end
