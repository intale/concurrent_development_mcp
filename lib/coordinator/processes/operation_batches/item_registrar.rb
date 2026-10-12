# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class ItemRegistrar
      include Dry::Monads[:result]

      def initialize(event_store:, loader: Coordinator::Write::OperationBatches::Loader.new(event_store:),
        registration: Coordinator::Write::Operations::ExecuteRegisterOperationBatchItemCommand.new(event_store:),
        assignment: Coordinator::Write::Operations::ExecuteAssignOperationBatchItemCommand.new(event_store:))
        @loader, @registration, @assignment = loader, registration, assignment
      end

      def call_command(command, caused_by:)
        snapshot = @loader.item(command.batch_id, command.index)
        item = snapshot.state.item(command.index)
        previous = snapshot.physical_events.find { %w[OperationBatchItemCommandAssigned OperationBatchItemRegistrationRejected].include?(_1.type) }
        return Success(Coordinator::Write::OperationBatches::AssignmentV1.new(item:, event: previous)) if previous
        return @assignment.call_command(command, caused_by:) unless item

        registered = @registration.call_command(Coordinator::Write::Commands::RegisterOperationBatchItemCommand.new(
          command_id: item.command_id, actor: command.actor, batch_id: command.batch_id, index: command.index), caused_by:)
        return registered if registered.failure?
        @assignment.call_command(command, caused_by:)
      end
    end
  end
end
