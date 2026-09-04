# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionSetLoader
    def initialize(event_store:, schema_registry: EventSchemaRegistry.new, stream_factory: StreamFactory.new)
      @event_store = event_store
      @schema_registry = schema_registry
      @stream_factory = stream_factory
    end

    def call(set_id)
      events = @event_store.read(
        @stream_factory.work_intention_set(set_id),
        EventQueries::WORK_INTENTION_SET_STATE
      )
      Domain::WorkIntentions::SetState.reduce(events.map { deserialize(_1) })
    end

    def find_by_attempt(attempt_id)
      event = @event_store.read_global_marked(
        EventQueries.work_intention_set_for_attempt("attempt:#{attempt_id}")
      ).first
      event && call(event.data.fetch("set_id"))
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
