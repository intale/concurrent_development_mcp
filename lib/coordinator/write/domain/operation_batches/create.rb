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

          event = Events::OperationBatchCreatedV2.new(
            batch_id: command.batch_id,
            target_tool: command.target_tool,
            page_size: command.page_size,
            items:
          )
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.operation_batch(command.batch_id), event:) ]
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
