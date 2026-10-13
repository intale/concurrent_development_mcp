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
        unless state.numbers_initialized?
          return Failure(OutcomeError.new(code: :operation_batch_numbers_uninitialized,
            message: "Batch numbers must be initialized from authoritative history", details: { batch_id: command.batch_id }))
        end
        stream = StreamFactory.new.operation_batch(command.batch_id)
        events = [
          Events::OptimisticSagas::OperationBatchItemFailedV1.new(
            batch_id: command.batch_id, index: command.index, **command.failure.to_h),
          Events::ProjectionNumbers::OperationBatchUnsuccessfulItemsNumberChangedV1.new(
            batch_id: command.batch_id, items_number: state.unsuccessful_items_number + 1)
        ]
        Success(Coordinator::Write::Domain::EventPlan.new(writes: events.map do
          Coordinator::Write::Domain::EventWrite.new(stream:, event: _1)
        end))
      end
    end
  end
end
