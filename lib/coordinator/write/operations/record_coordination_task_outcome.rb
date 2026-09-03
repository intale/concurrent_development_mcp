# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class RecordCoordinationTaskOutcome
      def initialize(
        transition:,
        decider: Domain::CoordinationTasks::RecordOutcome.new
      )
        @transition = transition
        @decider = decider
      end

      def call(task_id:, outcome:, caused_by: nil)
        @transition.call(
          command: Commands::RecordCoordinationTaskOutcome.new(
            task_id:,
            outcome:
          ),
          decider: @decider,
          transition_name: "outcome",
          caused_by:
        )
      end
    end
  end
end
