# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CoordinationTasks
      class AcknowledgeInput
        include Dry::Monads[:result]

        def call(state:, command:)
          if state.absent?
            return Failure(
              Tasks::LifecycleError.new(
                code: :task_not_found,
                message: "Task does not exist",
                task_id: command.task_id
              )
            )
          end

          Success(nil)
        end
      end
    end
  end
end
