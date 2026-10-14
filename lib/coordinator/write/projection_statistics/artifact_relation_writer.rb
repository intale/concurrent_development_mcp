# frozen_string_literal: true

module Coordinator::Write
  module ProjectionStatistics
    class ArtifactRelationWriter
      POLICY_VERSION = "development-artifact-relation-statistics/v1"

      def initialize(event_store:, event_factory: EventFactory.new, markers: ArtifactRelationMarkers.new)
        @event_store, @event_factory, @markers = event_store, event_factory, markers
      end

      def call(plan:, command_id:, actor:, artifact_id:, event_ids:, caused_by:,
        correlation_id:, source_event_id: nil, expected_revision: nil)
        events = plan.events.zip(event_ids).map do |event, event_id|
          markers = @markers.call(command_id:, artifact_id:, source_event_id:)
          case event.class.event_type
          when "DevelopmentArtifactRelationStatisticsAssigned"
            markers << @markers.owner(artifact_id)
          when "DevelopmentArtifactRelationsReconciliationFailed"
            markers << @markers.failure_command(command_id)
          end
          @event_factory.build!(event:, event_id:, markers:, caused_by:, correlation_id:,
            metadata: EventMetadata.new(command_id:, actor_kind: actor.kind, actor_id: actor.id,
              recorded_by: "coordinator", policy_version: POLICY_VERSION))
        end
        stream = plan.writes.first.stream
        if expected_revision.nil?
          @event_store.append(stream, events)
        else
          @event_store.append(stream, events, expected_revision:)
        end
      end
    end
  end
end
