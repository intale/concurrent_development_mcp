# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class ResultMapper
      def created(state)
        ResultV1::Created.new(
          common_attributes(state).merge(
            resultType: "task",
            status: "working"
          )
        )
      end

      def detailed(state)
        case state.status
        when "working"
          working(state)
        when "completed"
          ResultV1::Completed.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "completed",
              result: call_tool_result(state.result)
            )
          )
        when "failed"
          ResultV1::Failed.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "failed",
              statusMessage: state.status_message,
              error: state.error
            )
          )
        when "cancelled"
          ResultV1::Cancelled.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "cancelled",
              statusMessage: state.status_message
            )
          )
        else
          raise KeyError, "Task state is not protocol-visible"
        end
      end

      def acknowledgement
        ResultV1::Acknowledgement.new(resultType: "complete")
      end

      private

      def working(state)
        attributes = common_attributes(state).merge(
          resultType: "complete",
          status: "working"
        )
        return ResultV1::Working.new(attributes) unless state.status_message

        ResultV1::WorkingWithMessage.new(
          attributes.merge(statusMessage: state.status_message)
        )
      end

      def common_attributes(state)
        {
          taskId: state.task_id,
          createdAt: state.created_at,
          lastUpdatedAt: state.last_updated_at,
          ttlMs: state.ttl_ms,
          pollIntervalMs: state.poll_interval_ms
        }
      end

      def call_tool_result(result)
        ResultV1::CallToolResult.new(
          content: result.content,
          isError: result.is_error,
          structuredContent: result.structured_content
        )
      end
    end
  end
end
