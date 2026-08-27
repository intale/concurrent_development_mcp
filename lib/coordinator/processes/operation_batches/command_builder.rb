# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class CommandBuilder
      SYSTEM_ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "operation-batch-runner"
      )

      def record_outcome(source:, item:, result:, completion:)
        Coordinator::Write::Commands::RecordOperationBatchItemOutcome.new(
          command_id: command_id("outcome", source:, suffix: item.index),
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id,
          index: item.index,
          item_command_id: item.command_input.command_id,
          canonical_input_digest: item.canonical_input_digest,
          result:,
          target_completion: completion&.reference,
          finished_at: timestamp(completion&.event || source.event)
        )
      end

      def continuation(source:, page_start:, page_end:)
        Coordinator::Write::Commands::RequestOperationBatchContinuation.new(
          command_id: command_id("continue", source:, suffix: page_start),
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id,
          page_start:,
          page_end:,
          source_event: source.reference,
          requested_at: timestamp(source.event)
        )
      end

      def complete(source:)
        Coordinator::Write::Commands::CompleteOperationBatch.new(
          command_id: command_id("complete", source:),
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id,
          source_event: source.reference,
          completed_at: timestamp(source.event)
        )
      end

      def complete_cancellation(source:)
        Coordinator::Write::Commands::CompleteOperationBatchCancellation.new(
          command_id: command_id("cancel", source:),
          actor: SYSTEM_ACTOR,
          batch_id: source.payload.batch_id,
          source_event: source.reference,
          cancelled_at: timestamp(source.event)
        )
      end

      private

      def command_id(kind, source:, suffix: nil)
        components = [ "batch", kind, source.payload.batch_id, source.reference.event_id, suffix ]
        InternalCommandIdBuilder.call(components.compact.join(":"))
      end

      def timestamp(event)
        event.created_at.utc.iso8601(6)
      end
    end
  end
end
