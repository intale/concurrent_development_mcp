# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpirySourceBuilder
    def initialize(
      contract: Contracts::LeaseExpirySourceEvent.new,
      schema_registry: Coordinator::Write::EventSchemaRegistry.new
    )
      @contract = contract
      @schema_registry = schema_registry
    end

    def call(event)
      result = @contract.call(event:)
      raise InvalidSourceEvent, result.errors.to_h.inspect if result.failure?

      payload = @schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )

      LeaseExpirySource.new(
        event:,
        reference: Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        ),
        payload:
      )
    rescue Dry::Struct::Error, Coordinator::Write::EventSchemaRegistry::UnknownSchema, Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
      raise InvalidSourceEvent, error.message
    end
  end
end
