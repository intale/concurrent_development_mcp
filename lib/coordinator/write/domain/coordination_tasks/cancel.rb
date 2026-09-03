# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CoordinationTasks
      class Cancel
        include Dry::Monads[:result]

        def call(state:, command:)
          return Failure(task_not_found(command.task_id)) if state.absent?
          return Success(nil) if state.terminal? || state.cancellation_requested

          event = if state.started
                    Events::CoordinationTaskCancellationRequestedV2.new(
                      task_id: command.task_id,
                      reason: command.reason
                    )
          else
                    Events::CoordinationTaskCancelledV2.new(
                      task_id: command.task_id,
                      reason: command.reason || "Cancelled before execution"
                    )
          end

          Success(event)
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
