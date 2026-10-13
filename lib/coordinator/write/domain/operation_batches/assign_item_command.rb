# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class AssignItemCommand
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, registration:)
          item = state.item(command.index)
          return Failure(error(:operation_batch_not_found, "Batch does not exist", command)) unless state.creation
          return Failure(error(:operation_batch_item_not_found, "Batch item does not exist", command)) unless item
          return Success(nil) if state.assignment(command.index)
          return Failure(error(:operation_batch_item_already_recorded, "Batch item already has an outcome", command)) if state.outcome(command.index)
          return Failure(error(:operation_batch_terminal, "Batch is already terminal", command)) if state.terminal
          return Failure(error(:operation_batch_cancellation_pending, "Batch cancellation was requested", command)) if state.cancellation

          if registration && (registration.payload.tool_name != item.tool_name ||
                              registration.canonical_input_digest != item.canonical_input_digest)
            unless state.numbers_initialized?
              return Failure(error(:operation_batch_numbers_uninitialized, "Batch numbers must be initialized from authoritative history", command))
            end
            return Success(rejection(command, item:, registration:, state:))
          end

          command_id = registration ? registration.payload.command_id : item.command_id
          assignment = Events::OperationBatchItemCommandAssignedV1.new(
            batch_id: command.batch_id, index: command.index, command_id:
          )
          writes = [ EventWrite.new(stream: @stream_factory.operation_batch(command.batch_id), event: assignment) ]
          Success(EventPlan.new(writes:))
        end

        private

        def rejection(command, item:, registration:, state:)
          rejection = Tasks::DomainErrorV1::CommandIdReusedError.new(
            code: "command_id_reused",
            message: "Batch item request ID is already bound to another tool or input",
            details: Tasks::DomainErrorV1::CommandIdReusedDetails.new(
              command_id: item.request_id,
              existing_tool_name: registration.payload.tool_name,
              existing_input_digest: registration.canonical_input_digest,
              requested_tool_name: item.tool_name,
              requested_input_digest: item.canonical_input_digest
            )
          )
          stream = @stream_factory.operation_batch(command.batch_id)
          EventPlan.new(writes: [ EventWrite.new(
            stream:,
            event: Events::OperationBatchItemRegistrationRejectedV1.new(
              batch_id: command.batch_id, index: command.index, error: rejection
            )
          ), EventWrite.new(stream:, event: Events::ProjectionNumbers::OperationBatchUnsuccessfulItemsNumberChangedV1.new(
            batch_id: command.batch_id, items_number: state.unsuccessful_items_number + 1
          )) ])
        end

        def error(code, message, command)
          OutcomeError.new(code:, message:, details: { batch_id: command.batch_id, index: command.index })
        end
      end
    end
  end
end
