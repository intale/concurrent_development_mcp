# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class TargetCompletionLoader
      def initialize(
        event_store:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(command_id)
        event = @event_store.read(
          @stream_factory.command(command_id),
          Coordinator::Write::EventQueries::COMMAND_COMPLETION
        ).first
        raise MissingOperationBatchTargetCompletion, "Target command completed without a durable completion" unless event

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        TargetCompletionV1.new(event:, payload:, reference: reference(event))
      end

      private

      def reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
