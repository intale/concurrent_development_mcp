# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class RecordItemOutcome
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return Failure(not_found(command)) unless state.creation
          return Failure(terminal(command)) if state.terminal
          return Failure(item_not_found(command)) unless state.item(command.index)
          return Failure(already_recorded(command)) if state.outcome(command.index)
          return Failure(rejection_mismatch(command)) unless rejection_matches_outcome?(command)

          event = if command.outcome == "rejected"
                    rejected_event(command)
          else
                    succeeded_event(command)
          end
          completion = Events::OperationBatchItemCompletionLinkedV1.new(
            batch_id: command.batch_id,
            index: command.index,
            command_id: command.item_command_id,
            completion: command.target_event
          )
          stream = @stream_factory.operation_batch(command.batch_id)
          Success(EventPlan.new(writes: [ event, completion ].map { EventWrite.new(stream:, event: _1) }))
        end

        private

        def succeeded_event(command)
          Events::OperationBatchItemSucceededV2.new(
            batch_id: command.batch_id,
            index: command.index,
            command_id: command.item_command_id
          )
        end

        def rejected_event(command)
          rejection = command.rejection
          Events::OperationBatchItemRejectedV2.new(
            batch_id: command.batch_id,
            index: command.index,
            command_id: command.item_command_id,
            code: rejection.code,
            reason: rejection.reason,
            retryable: rejection.retryable
          )
        end

        def not_found(command)
          error(:operation_batch_not_found, "Batch does not exist", command)
        end

        def terminal(command)
          error(:operation_batch_terminal, "Batch is already terminal", command)
        end

        def item_not_found(command)
          error(:operation_batch_item_not_found, "Batch item does not exist", command, index: command.index)
        end

        def already_recorded(command)
          error(:operation_batch_item_already_recorded, "Batch item already has an outcome", command, index: command.index)
        end

        def rejection_matches_outcome?(command)
          command.outcome == "rejected" ? !command.rejection.nil? : command.rejection.nil?
        end

        def rejection_mismatch(command)
          error(
            :operation_batch_item_rejection_mismatch,
            "Batch item rejection details do not match its outcome",
            command,
            index: command.index
          )
        end

        def error(code, message, command, details = {})
          OutcomeError.new(code:, message:, details: { batch_id: command.batch_id }.merge(details))
        end
      end
    end
  end
end
