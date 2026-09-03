# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class CancelCoordinationTask
      def initialize(
        transition:,
        decider: Domain::CoordinationTasks::Cancel.new
      )
        @transition = transition
        @decider = decider
      end

      def call(task_id:, reason: nil)
        @transition.call(
          command: Commands::CancelCoordinationTask.new(
            task_id:,
            reason:
          ),
          decider: @decider,
          transition_name: "cancel"
        )
      end
    end
  end
end
