# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class Decider
      def initialize(
        create: Domain::OperationBatches::Create.new,
        record_item_outcome: Domain::OperationBatches::RecordItemOutcome.new,
        request_continuation: Domain::OperationBatches::RequestContinuation.new,
        complete: Domain::OperationBatches::Complete.new,
        request_cancellation: Domain::OperationBatches::RequestCancellation.new,
        complete_cancellation: Domain::OperationBatches::CompleteCancellation.new
      )
        @create = create
        @record_item_outcome = record_item_outcome
        @request_continuation = request_continuation
        @complete = complete
        @request_cancellation = request_cancellation
        @complete_cancellation = complete_cancellation
      end

      def call(state:, command:, occurred_at:)
        case command
        when Commands::CreateOperationBatch then @create.call(state:, command:, occurred_at:)
        when Commands::RecordOperationBatchItemOutcome then @record_item_outcome.call(state:, command:)
        when Commands::RequestOperationBatchContinuation then @request_continuation.call(state:, command:)
        when Commands::CompleteOperationBatch then @complete.call(state:, command:)
        when Commands::CancelOperationBatch then @request_cancellation.call(state:, command:, occurred_at:)
        when Commands::CompleteOperationBatchCancellation then @complete_cancellation.call(state:, command:)
        end
      end
    end
  end
end
