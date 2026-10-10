# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class StartItem
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Failure(error(:operation_batch_not_found, "Batch does not exist", command)) unless state.creation
          return Failure(error(:operation_batch_terminal, "Batch is already terminal", command)) if state.terminal
          return Failure(error(:operation_batch_item_already_recorded, "Batch item already has an outcome", command)) if state.outcome(command.index)
          item = state.item(command.index)
          unless item && state.assignment(command.index)
            return Failure(error(:operation_batch_item_not_assigned, "Batch item has no canonical command assignment", command))
          end
          unless item.command_id == command.item_command_id && item.tool_name == command.tool_name &&
                 item.canonical_input_digest == command.canonical_input_digest
            return Failure(error(:operation_batch_item_assignment_mismatch, "Target does not match the authoritative item assignment", command))
          end
          return Success(nil) if state.started?(command.index)
          return Failure(error(:operation_batch_cancellation_pending, "Batch cancellation was requested", command)) if state.cancellation

          Success(EventPlan.new(writes: [ EventWrite.new(
            stream: @stream_factory.operation_batch(command.batch_id),
            event: Events::OperationBatchItemExecutionStartedV1.new(batch_id: command.batch_id, index: command.index)
          ) ]))
        end

        private

        def error(code, message, command)
          OutcomeError.new(code:, message:, details: { batch_id: command.batch_id, index: command.index })
        end
      end
    end
  end
end
