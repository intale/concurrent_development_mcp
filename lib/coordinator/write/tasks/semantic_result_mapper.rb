# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class SemanticResultMapper
      STATUS_BY_CODE = ToolResultMapper::STATUS_BY_CODE

      def call(result, command_id:, tool_name:)
        return success(result.value!, tool_name:) if result.success?

        rejection(result.failure, command_id:, tool_name:)
      end

      private

      def success(completion, tool_name:)
        contract = TargetContractRegistry.fetch(tool_name)
        data = contract.task_receipt_type[completion.data]
        if data.is_a?(CommandReceiptData::OperationBatchCompletion) &&
           (data.status == "cancelled" || data.rejected.positive? || data.failed.positive?)
          error = OutcomeError.new(code: data.status == "cancelled" ? :operation_batch_cancelled : :operation_batch_partial_failure,
            message: completion.summary, details: data.to_h)
          return rejection(error, command_id: completion.command_id, tool_name:, next_actions: completion.next_actions)
        end
        SemanticResultV1::Success.new(
          kind: "success",
          summary: completion.summary,
          command_id: completion.command_id,
          receipt: completion.receipt,
          data:,
          warnings: completion.warnings,
          next_actions: completion.next_actions,
          completion: CompletionGuaranteeBuilder.new.success(tool_name:, data:, emitted_events: completion.emitted_events)
        )
      end

      def rejection(error, command_id:, tool_name:, next_actions: nil)
        domain_error = DomainErrorV1::Type[
          {
            code: error.code.to_s,
            message: error.message,
            details: error.details
          }
        ]
        SemanticResultV1::DomainRejection.new(
          kind: "domain_rejection",
          status: STATUS_BY_CODE.fetch(error.code),
          summary: error.message,
          command_id:,
          error: domain_error,
          next_actions: next_actions || failure_next_actions(domain_error),
          completion: CompletionGuaranteeBuilder.new.rejection(tool_name:, error: domain_error)
        )
      end

      def failure_next_actions(domain_error)
        if domain_error.is_a?(DomainErrorV1::SkillRevisionConflictError)
          return [
            NextAction.new(
              tool: "skill_get",
              arguments: NextAction::SkillArguments.new(
                name: domain_error.details.name,
                scope: domain_error.details.scope
              )
            )
          ]
        end

        return [] unless domain_error.is_a?(DomainErrorV1::StaleDecisionContextError)

        [
          NextAction.new(
            tool: "decision_resolve",
            arguments: NextAction::DecisionResolutionArguments.new(
              topic_id: domain_error.details.topic_id,
              context: domain_error.details.context
            )
          )
        ]
      end
    end
  end
end
