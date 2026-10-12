# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteStartOperationBatchItem
      include Dry::Monads[:result]

      def initialize(
        event_store:, loader: OperationBatches::Loader.new(event_store:),
        decider: Domain::OperationBatches::StartItem.new, event_factory: EventFactory.new,
        stream_factory: StreamFactory.new, id_generator: IdGenerator.new,
        revision_retry: OptimisticRevisionRetry.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @event_factory = event_factory
        @stream_factory = stream_factory
        @id_generator = id_generator
        @revision_retry = revision_retry
      end

      def call_command(command, event_id: @id_generator.uuid_v7, caused_by:)
        @revision_retry.call { execute_attempt(command, event_id:, caused_by:) }
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(OutcomeError.new(code: :concurrency_conflict,
          message: "Batch changed concurrently; the request may succeed if retried",
          details: { command_id: command.command_id }))
      end

      private

      def execute_attempt(command, event_id:, caused_by:)
        stream = @stream_factory.operation_batch(command.batch_id)
        latest = @event_store.read_latest(stream, EventQueries::OPERATION_BATCH_STREAM_REVISION)
        snapshot = @loader.item_identity(command.batch_id, command.index)
        decision = @decider.call(state: snapshot.state, command:)
        return decision if decision.failure?

        payload = decision.value!&.events&.first
        unless payload
          return Success(snapshot.physical_events.find { _1.type == "OperationBatchItemExecutionStarted" })
        end

        event = @event_factory.build!(
          event: payload, event_id:,
          metadata: EventMetadata.new(
            command_id: command.command_id, actor_kind: command.actor.kind, actor_id: command.actor.id,
            recorded_by: "coordinator", policy_version: "operation-batch/v2"
          ),
          markers: [ "operation-batch:#{command.batch_id}", "batch-item:#{command.batch_id}:#{command.index}",
                     "command:#{command.command_id}" ], caused_by:
        )
        Success(@event_store.append(stream, [ event ], expected_revision: latest&.stream_revision || :no_stream).sole)
      end
    end
  end
end
