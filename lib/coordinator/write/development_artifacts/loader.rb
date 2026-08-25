# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class Loader
      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def load(artifact_id)
        events = @event_store.read(
          @stream_factory.development_artifact(artifact_id),
          EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
        ).map { load_event(_1) }

        Domain::DevelopmentArtifacts::State.reduce(events)
      end

      def captured?(artifact_id)
        @event_store.read(
          @stream_factory.development_artifact(artifact_id),
          EventQueries::DEVELOPMENT_ARTIFACT_CAPTURE
        ).any?
      end

      private

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
