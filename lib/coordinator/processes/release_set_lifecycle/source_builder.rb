# frozen_string_literal: true

module Coordinator::Processes
  module ReleaseSetLifecycle
    class SourceBuilder
      def initialize(
        contract: Contracts::ReleaseSetLifecycleSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @contract = contract
        @schema_registry = schema_registry
      end

      def call(event)
        validation = @contract.call(event:)
        if validation.failure?
          raise ReleaseSetLifecycleProcessRejected,
                "ReleaseSet lifecycle source is invalid: #{validation.errors.to_h.inspect}"
        end

        SourceV1.new(
          event:,
          reference: reference(event),
          payload: @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        )
      rescue Dry::Struct::Error, Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise ReleaseSetLifecycleProcessRejected, error.message
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
