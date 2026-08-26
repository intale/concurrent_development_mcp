# frozen_string_literal: true

module Coordinator::Write
  class RepositoryRegistrationLoader
    def initialize(
      event_store:,
      schema_registry: EventSchemaRegistry.new,
      stream_factory: StreamFactory.new
    )
      @event_store = event_store
      @schema_registry = schema_registry
      @stream_factory = stream_factory
    end

    def call(repository_id)
      event = @event_store.read(
        @stream_factory.repository(repository_id),
        EventQueries::REPOSITORY_REGISTRATION
      ).first
      return unless event

      @schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
    end
  end
end
