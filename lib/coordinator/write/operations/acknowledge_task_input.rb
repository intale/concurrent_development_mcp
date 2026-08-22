# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class AcknowledgeTaskInput
      def initialize(
        loader:,
        decider: Domain::CoordinationTasks::AcknowledgeInput.new
      )
        @loader = loader
        @decider = decider
      end

      def call(task_id:)
        command = Commands::AcknowledgeTaskInput.new(task_id:)
        state = @loader.call(task_id).state
        decision = @decider.call(state:, command:)
        return decision if decision.failure?

        Dry::Monads::Success(state)
      end
    end
  end
end
