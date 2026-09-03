# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class ResultMapper
      def initialize(semantic_presenter: SemanticResultPresenterV1.new)
        @semantic_presenter = semantic_presenter
      end

      def created(state)
        ResultV1::Created.new(
          common_attributes(state).merge(
            resultType: "task",
            status: "working"
          )
        )
      end

      def detailed(state, projected_result: nil)
        case state.status
        when "working"
          working(state)
        when "completed"
          ResultV1::Completed.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "completed",
              result: completed_result(projected_result)
            )
          )
        when "failed"
          ResultV1::Failed.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "failed",
              statusMessage: state.status_message,
              error: failed_error(state)
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

      def projection_pending(state)
        ResultV1::WorkingWithMessage.new(
          common_attributes(state).merge(
            resultType: "complete",
            status: "working",
            statusMessage: "Command completed; its result projection is catching up."
          )
        )
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

      def completed_result(projected_result)
        raise KeyError, "Completed Task result has not been projected yet" unless projected_result

        @semantic_presenter.call(projected_result)
      end

      def failed_error(state)
        Coordinator::Write::Tasks::JsonRpcErrorV1.new(
          code: -32_603,
          message: state.status_message
        )
      end
    end
  end
end
