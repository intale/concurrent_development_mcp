# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class CancelCoordinationTask
      def initialize(
        transition:,
        decider: Domain::CoordinationTasks::Cancel.new,
        clock: SystemClock.new
      )
        @transition = transition
        @decider = decider
        @clock = clock
      end

      def call(task_id:)
        @transition.call(
          command: Commands::CancelCoordinationTask.new(
            task_id:,
            requested_at: @clock.now
          ),
          decider: @decider,
          transition_name: "cancel"
        )
      end
    end
  end
end
