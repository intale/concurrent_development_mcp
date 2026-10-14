# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class Create
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, items:)
          return Failure(conflict(command)) if state.creation

          stream = @stream_factory.operation_batch(command.batch_id)
          events = [
            Events::OperationBatchCreatedV2.new(batch_id: command.batch_id),
            Events::OperationBatchTargetSelectedV1.new(
              batch_id: command.batch_id,
              target_tool: command.target_tool
            ),
            Events::ProjectionNumbers::OperationBatchManifestAcceptedV1.new(batch_id: command.batch_id),
            Events::ProjectionNumbers::OperationBatchSucceededItemsNumberChangedV1.new(batch_id: command.batch_id, items_number: 0),
            Events::ProjectionNumbers::OperationBatchUnsuccessfulItemsNumberChangedV1.new(batch_id: command.batch_id, items_number: 0),
            *items.map do |item|
              Events::OperationBatchItemEnqueuedV1.new(
                batch_id: command.batch_id,
                index: item.index,
                command_id: item.command_id,
                input: item.submitted_input
              )
            end
          ]
          Success(
            EventPlan.new(
              writes: events.map { EventWrite.new(stream:, event: _1) }
            )
          )
        end

        private

        def conflict(command)
          OutcomeError.new(
            code: :operation_batch_id_conflict,
            message: "Batch ID is already in use",
            details: { batch_id: command.batch_id }
          )
        end
      end
    end
  end
end
