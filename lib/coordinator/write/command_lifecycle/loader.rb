# frozen_string_literal: true

module Coordinator::Write
  module CommandLifecycle
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

      def call(command_id)
        events = @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_HISTORY
        )
        payloads = events.map do |event|
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        end

        Snapshot.new(
          state: Domain::CommandLifecycles::State.reduce(
            payloads,
            canonical_input_digests: events.map { _1.metadata["canonical_input_digest"] }
          ),
          latest_revision: events.last&.stream_revision,
          persisted_events: events
        )
      end
    end
  end
end
