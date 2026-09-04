# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionLoader
    def initialize(event_store:, schema_registry: EventSchemaRegistry.new, stream_factory: StreamFactory.new)
      @event_store = event_store
      @schema_registry = schema_registry
      @stream_factory = stream_factory
    end

    def call(intention_id)
      events = @event_store.read_grouped(
        @stream_factory.resource_work_intention(intention_id),
        EventQueries::WORK_INTENTION_STATE
      ).reverse

      LoadedWorkIntentionV1.new(
        state: Domain::WorkIntentions::State.reduce(events.map { deserialize(_1) }),
        stream_revision: events.last&.stream_revision
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
  end
end
