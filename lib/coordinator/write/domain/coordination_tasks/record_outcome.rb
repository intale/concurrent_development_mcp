# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CoordinationTasks
      class RecordOutcome
        include Dry::Monads[:result]

        def call(state:, command:)
          return Failure(task_not_found(command.task_id)) if state.absent?
          return Success(nil) if state.terminal?
          return Failure(task_not_started(command.task_id)) unless state.started

          Success(build_event(command))
        end

        private

        def build_event(command)
          case command.outcome
          when Tasks::OutcomeV3::Completed
            Events::CoordinationTaskCompletedV3.new(task_id: command.task_id)
          when Tasks::OutcomeV3::Failed
            Events::CoordinationTaskFailedV2.new(
              task_id: command.task_id,
              code: command.outcome.code,
              reason: command.outcome.reason,
              retryable: command.outcome.retryable
            )
          end
        end

        def task_not_found(task_id)
          Tasks::LifecycleError.new(
            code: :task_not_found,
            message: "Task does not exist",
            task_id:
          )
        end

        def task_not_started(task_id)
          Tasks::LifecycleError.new(
            code: :task_not_started,
            message: "Task execution has not started",
            task_id:
          )
        end
      end
    end
  end
end
