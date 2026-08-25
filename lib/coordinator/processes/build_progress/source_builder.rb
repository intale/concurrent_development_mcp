# frozen_string_literal: true

module Coordinator::Processes
  module BuildProgress
    class SourceBuilder
      def initialize(
        contract: Contracts::BuildProgressSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @contract = contract
        @schema_registry = schema_registry
      end

      def call(event)
        validation = @contract.call(event:)
        raise BuildProgressProcessRejected, validation.errors.to_h.inspect if validation.failure?

        SourceV1.new(
          event:,
          reference: Coordinator::Write::EventReference.new(
            event_id: event.id,
            type: event.type,
            stream_context: event.stream.context,
            stream_name: event.stream.stream_name,
            stream_id: event.stream.stream_id,
            stream_revision: event.stream_revision
          ),
          payload: @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        )
      rescue Dry::Struct::Error, Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise BuildProgressProcessRejected, error.message
      end
    end
  end
end
