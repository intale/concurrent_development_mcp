# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class SourceBuilder
      def initialize(schema_registry: Coordinator::Write::EventSchemaRegistry.new)
        @schema_registry = schema_registry
      end

      def call(event)
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        SourceV1.new(event:, payload:, reference: reference(event))
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
