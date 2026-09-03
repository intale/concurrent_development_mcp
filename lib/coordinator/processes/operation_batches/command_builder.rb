# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class CommandBuilder
      SYSTEM_ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "operation-batch-runner"
      )

      def record_outcome(source:, item:, execution:, command_id:)
        Coordinator::Write::Commands::RecordOperationBatchItemOutcome.new(
          command_id:,
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id,
          index: item.index,
          item_command_id: item.command_id,
          outcome: execution.command_state.status,
          target_event: event_reference(execution.terminal_event)
        )
      end

      def continuation(source:, page_start:, page_end:, command_id:)
        Coordinator::Write::Commands::RequestOperationBatchContinuation.new(
          command_id:,
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id,
          page_start:,
          page_end:
        )
      end

      def complete(source:, command_id:)
        Coordinator::Write::Commands::CompleteOperationBatch.new(
          command_id:,
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id
        )
      end

      def complete_cancellation(source:, command_id:)
        Coordinator::Write::Commands::CompleteOperationBatchCancellation.new(
          command_id:,
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id
        )
      end

      private

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
