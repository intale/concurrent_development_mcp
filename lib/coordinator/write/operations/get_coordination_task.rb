# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class GetCoordinationTask
      include Dry::Monads[:result]

      def initialize(loader:)
        @loader = loader
      end

      def call(task_id:)
        state = @loader.call(task_id).state
        return Success(state) unless state.absent?

        Failure(
          Tasks::LifecycleError.new(
            code: :task_not_found,
            message: "Task does not exist",
            task_id:
          )
        )
      end
    end
  end
end
