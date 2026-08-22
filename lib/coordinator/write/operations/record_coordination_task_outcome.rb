# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class RecordCoordinationTaskOutcome
      def initialize(
        transition:,
        decider: Domain::CoordinationTasks::RecordOutcome.new,
        clock: SystemClock.new
      )
        @transition = transition
        @decider = decider
        @clock = clock
      end

      def call(task_id:, outcome:, caused_by: nil)
        @transition.call(
          command: Commands::RecordCoordinationTaskOutcome.new(
            task_id:,
            outcome:,
            recorded_at: @clock.now
          ),
          decider: @decider,
          transition_name: "outcome",
          caused_by:
        )
      end
    end
  end
end
