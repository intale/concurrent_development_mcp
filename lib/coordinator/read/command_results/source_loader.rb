# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class SourceLoader
      def initialize(
        event_store:,
        contract: Contracts::CommandTerminalSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new,
        target_command_builder: Coordinator::Write::Tasks::TargetCommandBuilder.new,
        batch_item_builder: Coordinator::Write::OperationBatches::ItemBuilder.new
      )
        @event_store = event_store
        @contract = contract
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @target_command_builder = target_command_builder
        @batch_item_builder = batch_item_builder
      end

      def call(event)
        validate_terminal!(event)
        command_events = @event_store.read(
          @stream_factory.command(event.stream.stream_id),
          Coordinator::Write::EventQueries::COMMAND_HISTORY
        )
        command_payloads = command_events.map { load_payload(_1) }
        command_state = CommandState.reduce(events: command_events, payloads: command_payloads)
        unless command_state.terminal? &&
               command_state.command_id == event.stream.stream_id &&
               command_events.last&.id == event.id
          raise InvalidProjectionSource, "Command terminal does not match its authoritative stream"
        end

        command_input = load_command_input(command_state, registration: command_events.first)
        return unless command_input

        persisted_events = load_persisted_events(event)
        Source.new(
          terminal_event: event,
          command_state:,
          command: @target_command_builder.call(command_input),
          persisted_events:,
          payloads: persisted_events.map { load_payload(_1) }
        )
      end

      private

      def validate_terminal!(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?
      end

      def load_command_input(command_state, registration:)
        task_submission = find_task_submission(command_state.command_id)
        return validated_command_input(
          load_payload(task_submission).command_input,
          command_state:,
          registration:
        ) if task_submission

        batch_item = find_batch_item(command_state.command_id, registration:)
        unless batch_item
          # Internal policy commands have no client instruction or public result.
          # A missing instruction for a public command is still corrupt history.
          return unless Coordinator::Write::Tasks::TargetContractRegistry.tool_names.include?(command_state.tool_name)

          raise InvalidProjectionSource, "Command has no Task or Operation Batch instruction"
        end

        unless batch_item.request_id == command_state.request_id &&
               batch_item.canonical_input_digest == command_state.canonical_input_digest
          raise InvalidProjectionSource, "Operation Batch item does not match its Command registration"
        end

        validated_command_input(batch_item.command_input, command_state:, registration:)
      end

      def find_task_submission(command_id)
        event = @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorControl",
            stream_name: "CoordinationTask",
            event_types: [ "CoordinationTaskSubmitted" ],
            markers: [ "command:#{command_id}" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first

        event
      end

      def find_batch_item(command_id, registration:)
        batch_markers = registration.markers.grep(/\Aoperation-batch:/)
        item_markers = registration.markers.grep(/\Abatch-item:/)
        return unless batch_markers.one? && item_markers.one?

        batch_id = batch_markers.sole.delete_prefix("operation-batch:")
        event = @event_store.read_marked(
          @stream_factory.operation_batch(batch_id),
          Coordinator::Write::MarkedEventReadCriteria.new(
            event_type: "OperationBatchItemEnqueued",
            marker: item_markers.sole,
            maximum_count: 1,
            direction: :asc
          )
        ).first
        return unless event

        payload = load_payload(event)
        return unless payload.is_a?(Coordinator::Write::Events::OperationBatchItemEnqueuedV1)

        item = @batch_item_builder.call(event:, payload:)
        item if item.command_id == command_id
      end

      def validated_command_input(command_input, command_state:, registration:)
        command = @target_command_builder.call(command_input)
        actor_matches = registration.metadata.fetch("actor_kind") == command.actor.kind &&
                        registration.metadata.fetch("actor_id") == command.actor.id
        unless command.command_id == command_state.command_id &&
               command_input.tool_name == command_state.tool_name && actor_matches
          raise InvalidProjectionSource, "Persisted Command instruction does not match its registration"
        end

        command_input
      end

      def load_persisted_events(terminal)
        events = @event_store.read_command_events(
          Coordinator::Write::CommandEventReadCriteria.new(
            command_id: terminal.stream.stream_id,
            through_global_position: terminal.global_position,
            maximum_count: Coordinator::Shared::Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS
          )
        )
        unless events.all? { _1.metadata.fetch("command_id") == terminal.stream.stream_id }
          raise InvalidProjectionSource, "Command marker resolved a fact owned by another command"
        end

        events
      end

      def load_payload(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
