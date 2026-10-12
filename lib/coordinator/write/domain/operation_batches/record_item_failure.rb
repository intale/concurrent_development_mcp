# frozen_string_literal: true

module Coordinator::Write
  module Domain::OperationBatches
    class RecordItemFailure
      include Dry::Monads[:result]

      def call(state:, command:)
        return Success(nil) if state.outcome(command.index)
        unless state.creation && state.item(command.index) && !state.terminal
          return Failure(OutcomeError.new(code: :operation_batch_terminal,
            message: "Batch item is absent or already terminal", details: { batch_id: command.batch_id, index: command.index }))
        end
        Success(Events::OptimisticSagas::OperationBatchItemFailedV1.new(
          batch_id: command.batch_id, index: command.index, **command.failure.to_h))
      end
    end
  end
end
