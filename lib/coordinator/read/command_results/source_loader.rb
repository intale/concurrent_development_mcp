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
        batch_item_builder: Coordinator::Write::OperationBatches::ItemBuilder.new,
        instruction_loader: nil
      )
        @event_store = event_store
        @contract = contract
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @target_command_builder = target_command_builder
        @instruction_loader = instruction_loader || InstructionLoader.new(
          event_store:, schema_registry:, stream_factory:, target_command_builder:, batch_item_builder:
        )
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

        command_input = @instruction_loader.call(command_state, registration: command_events.first)
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
