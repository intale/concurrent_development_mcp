# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAssignOperationBatchItemCommand
      include Dry::Monads[:result]

      def initialize(
        event_store:, loader: OperationBatches::Loader.new(event_store:),
        decider: Domain::OperationBatches::AssignItemCommand.new,
        registration_loader: OperationBatches::RegistrationLoader.new(event_store:),
        stream_factory: StreamFactory.new,
        event_factory: EventFactory.new, id_generator: IdGenerator.new,
        revision_retry: OptimisticRevisionRetry.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @registration_loader = registration_loader
        @stream_factory = stream_factory
        @event_factory = event_factory
        @id_generator = id_generator
        @revision_retry = revision_retry
      end

      def call_command(command, caused_by: nil)
        event_ids = Array.new(2) { @id_generator.uuid_v7 }
        correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
        @revision_retry.call do
          latest = @event_store.read_latest(@stream_factory.operation_batch(command.batch_id), EventQueries::OPERATION_BATCH_STREAM_REVISION)
          snapshot = @loader.item(command.batch_id, command.index)
          item = snapshot.state.item(command.index)
          previous = snapshot.physical_events.find do |event|
            %w[OperationBatchItemCommandAssigned OperationBatchItemRegistrationRejected].include?(event.type)
          end
          next Success(OperationBatches::AssignmentV1.new(item:, event: previous)) if previous

          input_actor = item&.command_input&.input&.actor
          actor = input_actor && Commands::Actor.new(kind: input_actor.actor_kind, id: input_actor.actor_id)
          registration = actor && @registration_loader.call(actor:, request_id: item.request_id)
          if item && !registration
            next Failure(OutcomeError.new(code: :command_not_found, message: "Item request is not registered",
              details: { command_id: command.command_id }))
          end
          decision = @decider.call(state: snapshot.state, command:, registration:)
          next decision if decision.failure?

          plan = decision.value!
          assignment = persist(plan, command:, item:, actor:, event_ids:, correlation_id:, caused_by:,
                               expected_revision: latest&.stream_revision || :no_stream)
          if assignment.type == "OperationBatchItemCommandAssigned"
            document = item.command_input.class.new(item.command_input.attributes.merge(command_id: assignment.data.fetch("command_id")))
            item = OperationBatches::ItemV2.new(item.attributes.merge(command_input: document))
          end
          Success(OperationBatches::AssignmentV1.new(item:, event: assignment))
        end
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(OutcomeError.new(code: :concurrency_conflict,
          message: "Batch assignment changed concurrently; the request may succeed if retried",
          details: { command_id: command.command_id }))
      end

      private

      def persist(plan, command:, item:, actor:, event_ids:, correlation_id:, caused_by:, expected_revision:)
        write = plan.writes.sole
        unless write.stream == @stream_factory.operation_batch(command.batch_id)
          raise InvalidOperationBatchEventPlan, "Assignment writes only the Batch stream"
        end
        common = {
          command_id: command.command_id, actor_kind: command.actor.kind, actor_id: command.actor.id,
          recorded_by: "coordinator", policy_version: "operation-batch/v2"
        }
        metadata = write.event.is_a?(Events::OperationBatchItemCommandAssignedV1) ?
          Metadata::OperationBatchItemAssignmentV1.new(**common, canonical_input_digest: item.canonical_input_digest) :
          EventMetadata.new(common)
        event = @event_factory.build!(
          event: write.event, event_id: event_ids.first, metadata:,
          markers: [ "operation-batch:#{command.batch_id}", "batch-item:#{command.batch_id}:#{command.index}",
                     "command:#{command.command_id}" ], correlation_id:, caused_by:
        )
        @event_store.append(write.stream, [ event ], expected_revision:).sole
      end
    end
  end
end
