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
        load_with_revision(artifact_id).first
      end

      def load_with_revision(artifact_id)
        raw_events = @event_store.read(
          @stream_factory.development_artifact(artifact_id),
          EventReadCriteria.new(
            event_types: [
              "DevelopmentArtifactCreated", "DevelopmentArtifactScopeChanged",
              "DevelopmentArtifactTitleChanged", "DevelopmentArtifactKindChanged",
              "DevelopmentArtifactLabelAdded", "DevelopmentArtifactLabelRemoved",
              "DevelopmentArtifactSourceChanged", "DevelopmentArtifactContentChanged",
              "DevelopmentArtifactCaptured", "DevelopmentArtifactRelationDeclared",
              "DevelopmentArtifactRelationSuperseded"
            ],
            maximum_count: Types::DEVELOPMENT_ARTIFACT_HISTORY_MAXIMUM_COUNT,
            direction: :asc
          )
        )
        events = raw_events.map { load_event(_1) }

        metadata_by_event = raw_events.zip(events).to_h { |raw, payload| [ payload.object_id, raw.metadata ] }
        [
          Domain::DevelopmentArtifacts::State.reduce(events, metadata_by_event:),
          raw_events.last&.stream_revision || -1
        ]
      end

      def captured?(artifact_id)
        @event_store.read(
          @stream_factory.development_artifact(artifact_id),
          EventQueries::DEVELOPMENT_ARTIFACT_CAPTURE
        ).any?
      end

      def load_observation(observation_id)
        events = @event_store.read(
          @stream_factory.development_artifact_observation(observation_id),
          EventReadCriteria.new(
            event_types: [
              "DevelopmentArtifactObservationRecorded",
              "DevelopmentArtifactObservationFactLinked",
              "DevelopmentArtifactClassificationCorrectionRecorded",
              "DevelopmentArtifactObserved",
              "DevelopmentArtifactClassificationCorrected"
            ],
            maximum_count: Types::DEVELOPMENT_ARTIFACT_OBSERVATION_HISTORY_MAXIMUM_COUNT,
            direction: :asc
          )
        ).map { load_event(_1) }

        Domain::DevelopmentArtifacts::ObservationState.reduce(events)
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
