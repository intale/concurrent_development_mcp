# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class StartCoordinationTask
      def initialize(
        transition:,
        decider: Domain::CoordinationTasks::Start.new
      )
        @transition = transition
        @decider = decider
      end

      def call(task_id:, caused_by: nil)
        @transition.call(
          command: Commands::StartCoordinationTask.new(task_id:),
          decider: @decider,
          transition_name: "start",
          caused_by:
        )
      end
    end
  end
end
