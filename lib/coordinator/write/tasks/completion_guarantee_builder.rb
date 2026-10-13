# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class CompletionGuaranteeBuilder
      def success(tool_name:, data:, emitted_events:)
        effects = if data.is_a?(CommandReceiptData::OperationBatchCompletion)
                    data.effects
        elsif tool_name == "work_intention_set_renew"
                    emitted_events.any? { _1.type == "ResourceWorkIntentionRenewed" } ? "committed" : "unchanged"
        else
                    emitted_events.empty? ? "unchanged" : "committed"
        end
        guarantee(tool_name:, outcome: "succeeded", effects:)
      end

      def rejection(tool_name:, error:)
        outcome, effects = case error
        when DomainErrorV1::OperationBatchPartialFailureError
                            [ "partial_failure", error.details.effects ]
        when DomainErrorV1::OperationBatchCancelledError
                            [ "cancelled", error.details.effects ]
        when DomainErrorV1::SagaExecutionFailedError
                            [ error.details.effects_committed ? "partial_failure" : "failed",
                              error.details.effects_committed ? "partial" : "none" ]
        else
                            [ "denied", "none" ]
        end
        guarantee(tool_name:, outcome:, effects:)
      end

      private

      def guarantee(tool_name:, outcome:, effects:)
        CompletionGuaranteeV1.new(
          scope: TargetContractRegistry.fetch(tool_name).completion_scope,
          outcome:, effects:, read_back_required: false, read_models: "eventually_consistent"
        )
      end
    end
  end
end
