# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class Complete
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Failure(error(:operation_batch_not_found, "Batch does not exist", command)) unless state.creation
          return Failure(error(:operation_batch_terminal, "Batch is already terminal", command)) if state.terminal
          return Failure(error(:operation_batch_cancellation_pending, "Batch cancellation has been requested", command)) if state.cancellation
          unless state.pending_indexes.empty?
            return Failure(error(:operation_batch_items_pending, "Batch still has pending items", command))
          end

          events = [
            Events::ProjectionNumbers::OperationBatchOutcomeRecordedV1.new(
              batch_id: command.batch_id, outcome: state.rejected_count.positive? ? "completed_with_errors" : "completed"),
            Events::OperationBatchCompletedV2.new(batch_id: command.batch_id)
          ]
          stream = @stream_factory.operation_batch(command.batch_id)
          Success(
            EventPlan.new(
              writes: events.map { EventWrite.new(stream:, event: _1) }
            )
          )
        end

        private

        def error(code, message, command)
          OutcomeError.new(code:, message:, details: { batch_id: command.batch_id })
        end
      end
    end
  end
end
