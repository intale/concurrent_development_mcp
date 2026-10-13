# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordOperationBatchItemFailure
      include Dry::Monads[:result]

      def initialize(event_store:, loader: OperationBatches::Loader.new(event_store:),
        decider: Domain::OperationBatches::RecordItemFailure.new, stream_factory: StreamFactory.new,
        event_factory: EventFactory.new, id_generator: IdGenerator.new, revision_retry: OptimisticRevisionRetry.new)
        @event_store, @loader, @decider = event_store, loader, decider
        @stream_factory, @event_factory, @id_generator, @revision_retry = stream_factory, event_factory, id_generator, revision_retry
      end

      def call_command(command, caused_by:)
        event_ids = Array.new(2) { @id_generator.uuid_v7 }
        @revision_retry.call do
          stream = @stream_factory.operation_batch(command.batch_id)
          revision = @event_store.read_latest(stream, EventQueries::OPERATION_BATCH_STREAM_REVISION)&.stream_revision || :no_stream
          snapshot = @loader.item(command.batch_id, command.index)
          decision = @decider.call(state: snapshot.state, command:)
          next decision if decision.failure? || !decision.value!
          events = decision.value!.events.zip(event_ids).map do |payload, event_id|
            @event_factory.build!(event: payload, event_id:,
              metadata: EventMetadata.new(command_id: command.command_id, actor_kind: command.actor.kind,
                actor_id: command.actor.id, recorded_by: "coordinator", policy_version: "operation-batch/v2"),
              markers: [ "command:#{command.command_id}", "operation-batch:#{command.batch_id}",
                "batch-item:#{command.batch_id}:#{command.index}" ], caused_by:)
          end
          Success(@event_store.append(stream, events, expected_revision: revision).first)
        end
      end
    end
  end
end
