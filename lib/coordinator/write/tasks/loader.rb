# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class Loader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(task_id)
        events = @event_store.read(
          @stream_factory.coordination_task(task_id),
          EventQueries::COORDINATION_TASK_HISTORY
        )
        payloads = events.map do |event|
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        end

        Snapshot.new(
          state: Domain::CoordinationTasks::State.reduce(payloads),
          latest_revision: events.last&.stream_revision,
          persisted_events: events
        )
      end
    end
  end
end
