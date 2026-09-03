# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CoordinationTasks
      class State < Value
        attribute :task_id, Types::TaskId.optional
        attribute :status, Types::String.enum("absent", "working", "completed", "failed", "cancelled")
        attribute :status_message, Types::String.optional
        attribute :tool_name, Types::Identifier.optional
        attribute :command_id, Types::Identifier.optional
        attribute :command_input, CommandInputDocuments::Type.optional
        attribute :created_at, Types::Timestamp.optional
        attribute :last_updated_at, Types::Timestamp.optional
        attribute :ttl_ms, Types::Nil
        attribute :poll_interval_ms, Types::Integer.optional
        attribute :started, Types::Strict::Bool
        attribute :cancellation_requested, Types::Strict::Bool
        attribute :semantic_result, Tasks::SemanticResultV1::Type.optional
        attribute :error, Tasks::JsonRpcErrorV1.optional
        attribute :failure_code, Types::Identifier.optional
        attribute :failure_retryable, Types::Strict::Bool.optional

        def self.initial
          new(
            task_id: nil,
            status: "absent",
            status_message: nil,
            tool_name: nil,
            command_id: nil,
            command_input: nil,
            created_at: nil,
            last_updated_at: nil,
            ttl_ms: nil,
            poll_interval_ms: nil,
            started: false,
            cancellation_requested: false,
            semantic_result: nil,
            error: nil,
            failure_code: nil,
            failure_retryable: nil
          )
        end

        def self.reduce(events, occurred_at: [], contract: Contracts::CoordinationTaskHistory.new)
          validation = contract.call(events:)
          raise InvalidCoordinationTaskHistory, validation.errors.to_h.inspect if validation.failure?

          events.each_with_index.reduce(initial) do |state, (event, index)|
            state.apply(event, occurred_at: occurred_at[index])
          end
        end

        def absent?
          status == "absent"
        end

        def terminal?
          %w[completed failed cancelled].include?(status)
        end

        def apply(event, occurred_at: nil)
          attributes = case event
          when Events::CoordinationTaskSubmittedV2
                         {
                           task_id: event.task_id,
                           status: "working",
                           status_message: nil,
                           tool_name: event.tool_name,
                           command_id: event.command_id,
                           command_input: event.command_input,
                           created_at: event.submitted_at,
                           last_updated_at: event.submitted_at,
                           ttl_ms: event.ttl_ms,
                           poll_interval_ms: event.poll_interval_ms
                         }
          when Events::CoordinationTaskSubmittedV3
                         {
                           task_id: event.task_id,
                           status: "working",
                           status_message: nil,
                           tool_name: event.tool_name,
                           command_id: event.command_id,
                           command_input: event.command_input,
                           created_at: occurred_at,
                           last_updated_at: occurred_at,
                           ttl_ms: event.ttl_ms,
                           poll_interval_ms: event.poll_interval_ms
                         }
          when Events::CoordinationTaskExecutionStartedV1
                         { started: true, last_updated_at: event.started_at }
          when Events::CoordinationTaskExecutionStartedV2
                         { started: true, last_updated_at: occurred_at }
          when Events::CoordinationTaskCancellationRequestedV1
                         {
                           cancellation_requested: true,
                           status_message: "Cancellation requested; execution may still complete",
                           last_updated_at: event.requested_at
                         }
          when Events::CoordinationTaskCancellationRequestedV2
                         {
                           cancellation_requested: true,
                           status_message: event.reason || "Cancellation requested; execution may still complete",
                           last_updated_at: occurred_at
                         }
          when Events::CoordinationTaskCompletedV2
                         {
                           status: "completed",
                           status_message: nil,
                           semantic_result: event.result,
                           last_updated_at: event.completed_at
                         }
          when Events::CoordinationTaskCompletedV3
                         {
                           status: "completed",
                           status_message: nil,
                           last_updated_at: occurred_at
                         }
          when Events::CoordinationTaskFailedV1
                         {
                           status: "failed",
                           status_message: event.error.message,
                           error: event.error,
                           last_updated_at: event.failed_at
                         }
          when Events::CoordinationTaskFailedV2
                         {
                           status: "failed",
                           status_message: event.reason,
                           failure_code: event.code,
                           failure_retryable: event.retryable,
                           last_updated_at: occurred_at
                         }
          when Events::CoordinationTaskCancelledV1
                         {
                           status: "cancelled",
                           status_message: "Cancelled before execution",
                           last_updated_at: event.cancelled_at
                         }
          when Events::CoordinationTaskCancelledV2
                         {
                           status: "cancelled",
                           status_message: event.reason,
                           last_updated_at: occurred_at
                         }
          end

          self.class.new(to_h.merge(attributes))
        end
      end
    end
  end
end
