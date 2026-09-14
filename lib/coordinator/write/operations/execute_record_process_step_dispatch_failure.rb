# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordProcessStepDispatchFailure
      include Dry::Monads[:result]

      HISTORY = EventReadCriteria.new(
        event_types: [ "ProcessStepPlanned", "ProcessStepDispatchFailed" ],
        maximum_count: 2,
        direction: :asc
      )

      def initialize(
        event_store:,
        decider: Domain::ProcessSteps::RecordDispatchFailure.new,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        event_factory: EventFactory.new,
        id_generator: IdGenerator.new
      )
        @event_store = event_store
        @decider = decider
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @event_factory = event_factory
        @id_generator = id_generator
      end

      def call_command(command, caused_by:)
        stream = @stream_factory.process_step(command.process_step_id)
        physical = @event_store.read(stream, HISTORY)
        return Failure(not_found(command)) if physical.empty?

        state = ProcessSteps::DispatchState.reduce(physical.map { deserialize(_1) })
        decision = @decider.call(state:, command:)
        return decision if decision.failure? || decision.value!.nil?

        event = @event_factory.build!(
          event: decision.value!,
          event_id: @id_generator.uuid_v7,
          metadata: metadata(command),
          markers: [
            "command:#{command.command_id}",
            "target-command:#{command.target_command_id}"
          ],
          caused_by:
        )
        Success(@event_store.append(stream, [ event ], expected_revision: physical.last.stream_revision).sole)
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :concurrency_conflict,
            message: "Process step changed concurrently; the request may succeed if retried",
            details: { process_step_id: command.process_step_id }
          )
        )
      end

      private

      def deserialize(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def metadata(command)
        ProcessSteps::DispatchFailureMetadataV1.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          actor_authenticated: false,
          recorded_by: "coordinator",
          policy_version: "process-step-dispatch/v1",
          diagnostic_source: "process-manager-operation"
        )
      end

      def not_found(command)
        OutcomeError.new(
          code: :process_step_not_found,
          message: "Process step does not exist",
          details: { process_step_id: command.process_step_id }
        )
      end
    end
  end
end
