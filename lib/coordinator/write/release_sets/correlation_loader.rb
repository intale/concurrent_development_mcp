# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CorrelationLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(release_set_id)
        physical = @event_store.read(
          @stream_factory.release_set(release_set_id),
          EventQueries::RELEASE_SET_PREPARATION
        ).find { _1.type == "ReleaseSetPrepared" }
        return unless physical

        payload = @schema_registry.load(
          type: physical.type,
          schema_version: physical.metadata.fetch("schema_version"),
          data: physical.data
        )
        return unless payload.release_set_id == release_set_id

        physical.correlation_id
      end
    end
  end
end
