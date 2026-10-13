# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class BatchResultLoader
      def initialize(event_store:, loader: OperationBatches::Loader.new(event_store:), schema_registry: EventSchemaRegistry.new)
        @event_store, @loader, @schema_registry = event_store, loader, schema_registry
      end

      def call(command)
        snapshot = @loader.call(command.batch_id)
        state = snapshot.state
        terminal = snapshot.physical_events.find { _1.type == state.terminal.class.event_type } if state.terminal
        unless terminal && state.creation.batch_id == command.batch_id && state.target_selection.target_tool == command.target_tool
          raise InvalidOperationBatchHistory, "Completed Batch command has no matching terminal Saga"
        end
        failures = state.outcomes.select { failed?(_1) }
        not_run = state.pending_indexes.length
        if terminal.type == "OperationBatchCompleted" && not_run.positive?
          raise InvalidOperationBatchHistory, "Completed Batch still has unexecuted items"
        end
        succeeded = state.succeeded_count
        rejected = state.outcomes.length - succeeded - failures.length
        unless succeeded + rejected + failures.length + not_run == state.item_count
          raise InvalidOperationBatchHistory, "Batch outcome counts do not partition its manifest"
        end
        CommandReceiptData::OperationBatchCompletion.new(
          batch_id: command.batch_id, target_tool: command.target_tool, total: state.item_count,
          succeeded:, rejected:, failed: failures.length, not_run:,
          status: terminal.type == "OperationBatchCancelled" ? "cancelled" : "completed",
          effects: effects(state, failures:),
          completion_event: EventReference.new(event_id: terminal.id, type: terminal.type,
            stream_context: terminal.stream.context, stream_name: terminal.stream.stream_name,
            stream_id: terminal.stream.stream_id, stream_revision: terminal.stream_revision),
          completed_at: terminal.created_at.utc.iso8601(6)
        )
      end

      private

      def failed?(outcome)
        outcome.is_a?(Events::OptimisticSagas::OperationBatchItemFailedV1) ||
          (outcome.is_a?(Events::OperationBatchItemRejectedV2) && outcome.code == "saga_execution_failed")
      end

      def effects(state, failures:)
        return "committed" if state.succeeded_count == state.item_count
        return "partial" if state.succeeded_count.positive? || failures.any? do |failure|
          failure.is_a?(Events::OptimisticSagas::OperationBatchItemFailedV1) && failure.effects_committed
        end
        command_ids = failures.grep(Events::OperationBatchItemRejectedV2).map(&:command_id).uniq
        return "none" if command_ids.empty?

        events = @event_store.read_global_marked(GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl", stream_name: "Command", event_types: [ "CommandExecutionFailed" ],
          markers: command_ids.map { "command:#{_1}" }, maximum_count: command_ids.length, direction: :asc
        ))
        unless events.map { _1.stream.stream_id }.sort == command_ids.sort
          raise InvalidOperationBatchHistory, "Failed Batch item is missing its canonical failure fact"
        end
        events.any? { @schema_registry.load(type: _1.type, schema_version: _1.metadata.fetch("schema_version"), data: _1.data).effects_committed } ? "partial" : "none"
      end
    end
  end
end
