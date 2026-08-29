# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class SemanticResultMapper
      STATUS_BY_CODE = ToolResultMapper::STATUS_BY_CODE

      def call(result, command_id:, tool_name:)
        return success(result.value!, tool_name:) if result.success?

        rejection(result.failure, command_id:)
      end

      private

      def success(completion, tool_name:)
        contract = TargetContractRegistry.fetch(tool_name)
        SemanticResultV1::Success.new(
          kind: "success",
          summary: completion.summary,
          command_id: completion.command_id,
          receipt: completion.receipt,
          data: contract.receipt_type[completion.data],
          warnings: completion.warnings,
          next_actions: completion.next_actions
        )
      end

      def rejection(error, command_id:)
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
          next_actions: failure_next_actions(domain_error)
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
