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
            status: state.status,
            statusMessage: acceptance_message(state)
          )
        )
      end

      def detailed(state, semantic_result: nil)
        case state.status
        when "working"
          working(state)
        when "completed"
          result = completed_result(semantic_result)
          ResultV1::Completed.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "completed",
              statusMessage: result.structuredContent.summary,
              result:
            )
          )
        when "failed"
          ResultV1::Failed.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "failed",
              statusMessage: "#{state.status_message} This protocol failure does not establish whether target effects committed. Do not infer rollback or submit another write to confirm persistence.",
              error: failed_error(state)
            )
          )
        when "cancelled"
          ResultV1::Cancelled.new(
            common_attributes(state).merge(
              resultType: "complete",
              status: "cancelled",
              statusMessage: "#{state.status_message} Cancellation does not roll back previously committed effects or cancel other related operations."
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
        ResultV1::WorkingWithMessage.new(
          attributes.merge(statusMessage: acceptance_message(state))
        )
      end

      def acceptance_message(state)
        return "The original Task is #{state.status}; retrieve its authoritative outcome through task_get (or tasks/get for extension clients). Do not resubmit a new mutation to confirm persistence." if state.terminal?

        note = "The request is durably recorded, but its requested effects are not yet confirmed. Poll this Task at pollIntervalMs; entity reads may lag and cannot establish completion."
        [ state.status_message, note ].compact.join(" ")
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

      def completed_result(semantic_result)
        raise KeyError, "Completed Task has no authoritative result" unless semantic_result

        @semantic_presenter.call(semantic_result)
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
