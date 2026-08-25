# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module OperationBatches
      class Complete
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          canonical_json: CanonicalJson.new
        )
          @stream_factory = stream_factory
          @canonical_json = canonical_json
        end

        def call(state:, command:)
          return Failure(error(:operation_batch_not_found, "Batch does not exist", command)) unless state.creation
          return Failure(error(:operation_batch_terminal, "Batch is already terminal", command)) if state.terminal
          return Failure(error(:operation_batch_cancellation_pending, "Batch cancellation has been requested", command)) if state.cancellation
          unless state.pending_indexes.empty?
            return Failure(error(:operation_batch_items_pending, "Batch still has pending items", command))
          end

          event = Events::OperationBatchCompletedV1.new(
            batch_id: command.batch_id,
            succeeded: state.succeeded_count,
            rejected: state.rejected_count,
            outcome_manifest_digest: outcome_manifest_digest(state),
            completed_at: command.completed_at
          )
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.operation_batch(command.batch_id), event:) ]
            )
          )
        end

        private

        def outcome_manifest_digest(state)
          @canonical_json.sha256(
            state.outcomes.sort_by(&:index).map do |outcome|
              {
                index: outcome.index,
                command_id: outcome.command_id,
                canonical_input_digest: outcome.canonical_input_digest,
                status: outcome.is_a?(Events::OperationBatchItemSucceededV1) ? "succeeded" : "rejected"
              }
            end
          )
        end

        def error(code, message, command)
          OutcomeError.new(code:, message:, details: { batch_id: command.batch_id })
        end
      end
    end
  end
end
