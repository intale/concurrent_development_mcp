# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class Create
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, occurred_at:)
          return Failure(conflict(command)) if state.creation

          event = Events::OperationBatchCreatedV1.new(
            batch_id: command.batch_id,
            target_tool: command.target_tool,
            total: command.items.length,
            page_size: command.page_size,
            items: command.items,
            manifest_digest: command.manifest_digest,
            encoded_byte_size: command.encoded_byte_size,
            requester: Coordinator::Write::OperationBatches::ActorV1.new(
              kind: command.actor.kind,
              id: command.actor.id
            ),
            created_at: occurred_at
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
