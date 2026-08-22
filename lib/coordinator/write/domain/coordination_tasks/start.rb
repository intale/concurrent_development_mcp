# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CoordinationTasks
      class Start
        include Dry::Monads[:result]

        def call(state:, command:)
          return Failure(task_not_found(command.task_id)) if state.absent?
          return Success(nil) if state.terminal? || state.started || state.cancellation_requested

          Success(
            Events::CoordinationTaskExecutionStartedV1.new(
              task_id: command.task_id,
              started_at: command.started_at
            )
          )
        end

        private

        def task_not_found(task_id)
          Tasks::LifecycleError.new(
            code: :task_not_found,
            message: "Task does not exist",
            task_id:
          )
        end
      end
    end
  end
end
