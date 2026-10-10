# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ItemExecutor
      include Dry::Monads[:result]

      def initialize(
        event_store:, target_builder: Tasks::TargetCommandBuilder.new,
        target_executor: Tasks::TargetExecutor.new(event_store:),
        start_item: Operations::ExecuteStartOperationBatchItem.new(event_store:),
        id_generator: IdGenerator.new
      )
        @event_store = event_store
        @target_builder = target_builder
        @target_executor = target_executor
        @start_item = start_item
        @id_generator = id_generator
      end

      def call(command:, item:, caused_by:)
        target = @target_builder.call(item.command_input)
        preparation = @target_executor.prepare(target, caused_by:)
        event_id = @id_generator.uuid_v7
        @event_store.multiple do
          started = @start_item.call_in_transaction(command, event_id:, caused_by:)
          next started if started.failure?

          result = @target_executor.call_prepared(target, preparation:, caused_by: started.value!)
          # An unexpected target failure must roll back the newly persisted start.
          Success(result.value!)
        end
      end
    end
  end
end
