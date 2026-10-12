# frozen_string_literal: true

module Coordinator::Processes::OperationBatches
  class ItemExecutor
      include Dry::Monads[:result]

      def initialize(
        event_store:, target_builder: Coordinator::Write::Tasks::TargetCommandBuilder.new,
        target_executor: Coordinator::Processes::TargetCommandExecutor.new(event_store:),
        start_item: Coordinator::Write::Operations::ExecuteStartOperationBatchItem.new(event_store:),
        id_generator: Coordinator::Write::IdGenerator.new
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
        started = @start_item.call_command(command, event_id:, caused_by:)
        return started if started.failure?

        @target_executor.call_prepared(target, preparation:, caused_by: started.value!)
      end
  end
end
