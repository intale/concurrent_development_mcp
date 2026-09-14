# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class RequestContinuation
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Failure(error(:operation_batch_not_found, "Batch does not exist", command)) unless state.creation
          return Failure(error(:operation_batch_terminal, "Batch is already terminal", command)) if state.terminal
          return Failure(error(:operation_batch_cancellation_pending, "Batch cancellation has been requested", command)) if state.cancellation
          return Failure(error(:operation_batch_ready_to_complete, "Batch has no remaining items", command)) if state.pending_indexes.empty?
          unless valid_page?(state, command)
            return Failure(error(:operation_batch_continuation_invalid, "Continuation page does not match pending items", command))
          end

          event = Events::OperationBatchContinuationRequestedV2.new(
            batch_id: command.batch_id,
            page_start: command.page_start,
            page_end: command.page_end
          )
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.operation_batch(command.batch_id), event:) ]
            )
          )
        end

        private

        def valid_page?(state, command)
          first = state.pending_indexes.min
          expected_end = [ first + state.processing_page_size - 1, state.items.length - 1 ].min
          command.page_start == first && command.page_end == expected_end
        end

        def error(code, message, command)
          OutcomeError.new(code:, message:, details: { batch_id: command.batch_id })
        end
      end
    end
  end
end
