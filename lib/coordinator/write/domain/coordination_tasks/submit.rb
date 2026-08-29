# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CoordinationTasks
      class Submit
        include Dry::Monads[:result]

        def call(state:, command:)
          unless state.absent?
            return Failure(
              Tasks::LifecycleError.new(
                code: :task_id_collision,
                message: "Generated Task ID is already in use",
                task_id: command.task_id
              )
            )
          end

          Success(
            Events::CoordinationTaskSubmittedV2.new(
              task_id: command.task_id,
              tool_name: command.tool_name,
              command_id: command.command_id,
              command_input: command.command_input,
              submitted_at: command.submitted_at,
              ttl_ms: command.ttl_ms,
              poll_interval_ms: command.poll_interval_ms
            )
          )
        end
      end
    end
  end
end
