# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class OperationBatches
      TOOLS = %w[skill_publish_batch development_artifact_capture_batch development_artifact_relation_declare_batch operation_batch_cancel].freeze

      def initialize(facts:)
        @facts = facts
      end

      def call(source)
        if source.tool_name == "operation_batch_cancel"
          return source.presentation("Operation Batch cancellation requested; completed items remain committed.",
            source.values(:batch_id).merge(status: "cancellation_requested"), next_actions: actions(source))
        end

        events = @facts.history(:operation_batch, source.input.fetch(:batch_id),
          Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY.event_types,
          maximum_count: Coordinator::Shared::Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS)
          .select { _1.global_position <= source.terminal_event.global_position }
        terminal = events.reverse.find { %w[OperationBatchCompleted OperationBatchCancelled].include?(_1.type) }
        total = events.find { _1.type == "OperationBatchManifestAccepted" }.metadata.fetch("item_count")
        succeeded = events.reverse.find { _1.type == "OperationBatchSucceededItemsNumberChanged" }.data.fetch("items_number")
        unsuccessful = events.reverse.find { _1.type == "OperationBatchUnsuccessfulItemsNumberChanged" }.data.fetch("items_number")
        failures = events.select { _1.type == "OperationBatchItemFailed" || (_1.type == "OperationBatchItemRejected" && _1.data.fetch("code") == "saga_execution_failed") }
        failed = failures.length
        rejected = unsuccessful - failed
        not_run = total - succeeded - unsuccessful
        status = terminal.type == "OperationBatchCancelled" ? "cancelled" : "completed"
        effects = effects(source, total:, succeeded:, failures:)
        source.presentation("Operation Batch settled: #{succeeded} succeeded, #{rejected} rejected, #{failed} failed, #{not_run} not run.",
          source.values(:batch_id, :target_tool).merge(total:, succeeded:, rejected:, failed:, not_run:, status:, effects:,
            completion_event: source.reference(terminal), completed_at: source.timestamp(terminal)), next_actions: actions(source))
      end

      private

      def actions(source)
        [ source.action("operation_batch_get", **source.values(:batch_id)) ]
      end

      def effects(source, total:, succeeded:, failures:)
        return "committed" if succeeded == total
        return "partial" if succeeded.positive? || failures.any? { _1.type == "OperationBatchItemFailed" && _1.data.fetch("effects_committed") }

        committed = failures.select { _1.type == "OperationBatchItemRejected" }.any? do |event|
          fact = @facts.first(:command, event.data.fetch("command_id"), "CommandExecutionFailed")
          fact.data.fetch("effects_committed")
        end
        committed ? "partial" : "none"
      end
    end
  end
end
