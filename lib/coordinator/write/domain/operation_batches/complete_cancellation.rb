# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class CompleteCancellation
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Failure(error(:operation_batch_not_found, "Batch does not exist", command)) unless state.creation
          return Failure(error(:operation_batch_terminal, "Batch is already terminal", command)) if state.terminal
          unless state.cancellation
            return Failure(error(:operation_batch_cancellation_not_requested, "Batch cancellation was not requested", command))
          end

          event = Events::OperationBatchCancelledV1.new(
            batch_id: command.batch_id,
            succeeded: state.succeeded_count,
            rejected: state.rejected_count,
            not_run: state.creation.total - state.outcomes.length,
            cancellation_event: command.source_event,
            cancelled_at: command.cancelled_at
          )
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.operation_batch(command.batch_id), event:) ]
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
