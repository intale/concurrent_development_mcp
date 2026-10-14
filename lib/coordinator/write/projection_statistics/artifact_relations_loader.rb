# frozen_string_literal: true

module Coordinator::Write
  module ProjectionStatistics
    class ArtifactRelationsLoader
      SOURCE_TYPES = %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded].freeze

      def initialize(event_store:, stream_factory: StreamFactory.new,
        registry: EventSchemaRegistry.new, markers: ArtifactRelationMarkers.new)
        @event_store, @stream_factory, @registry, @markers = event_store, stream_factory, registry, markers
      end

      def selector(artifact_id)
        NaturalKeys::Registry::SelectorV1.new(
          stream_context: "DevelopmentMemory", stream_name: "DevelopmentArtifactRelationStatistics",
          event_type: "DevelopmentArtifactRelationStatisticsAssigned", marker: @markers.owner(artifact_id)
        )
      end

      def state(statistics_id)
        events = @event_store.read_grouped(
          @stream_factory.development_artifact_relation_statistics(statistics_id),
          EventQueries::DEVELOPMENT_ARTIFACT_RELATION_STATISTICS_CONTROL
        )
        assignment = events.find { _1.type == "DevelopmentArtifactRelationStatisticsAssigned" }
        numbers = events.find { _1.type == "DevelopmentArtifactRelationsNumberChanged" }
        ArtifactRelationStateV1.new(
          statistics_id:, artifact_id: assignment&.data&.fetch("artifact_id"),
          active_relations_number: numbers&.data&.fetch("active_relations_number"),
          lifetime_relations_number: numbers&.data&.fetch("lifetime_relations_number"),
          latest_revision: events.first&.stream_revision || -1
        )
      end

      def source(reference, artifact_id:)
        return unless SOURCE_TYPES.include?(reference.type) &&
                      reference.stream_context == "DevelopmentMemory" &&
                      reference.stream_name == "DevelopmentArtifactRelation"

        event = @event_store.read_at(
          StreamReference.new(context: reference.stream_context,
            stream_name: reference.stream_name, stream_id: reference.stream_id),
          reference.stream_revision
        )
        return unless event && event.id == reference.event_id && event.type == reference.type &&
                      event.data.fetch("source_artifact_id") == artifact_id

        event
      end

      def reconciled?(statistics_id, source_event_id)
        marked?(statistics_id, "DevelopmentArtifactRelationsReconciled", @markers.source(source_event_id))
      end

      def failure_recorded?(statistics_id, command_id)
        marked?(statistics_id, "DevelopmentArtifactRelationsReconciliationFailed", @markers.failure_command(command_id))
      end

      def relation_states(artifact_id)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentMemory", stream_name: "DevelopmentArtifactRelation",
            event_types: SOURCE_TYPES, markers: [ "development-artifact:#{artifact_id}" ],
            maximum_count: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT * 2,
            direction: :asc
          )
        )
        events.group_by { _1.stream.stream_id }.values.map do |history|
          Domain::DevelopmentArtifacts::RelationStateV2.reduce(history.map do |event|
            @registry.load(type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data)
          end)
        end
      end

      private

      def marked?(statistics_id, event_type, marker)
        @event_store.read_marked(
          @stream_factory.development_artifact_relation_statistics(statistics_id),
          MarkedEventReadCriteria.new(event_type:, marker:, maximum_count: 1, direction: :asc)
        ).any?
      end
    end
  end
end
