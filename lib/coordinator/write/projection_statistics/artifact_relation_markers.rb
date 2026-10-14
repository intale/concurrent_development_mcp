# frozen_string_literal: true

module Coordinator::Write::ProjectionStatistics
  class ArtifactRelationMarkers
    def owner(artifact_id)
      "development-artifact-relation-statistics-owner:#{artifact_id}"
    end

    def source(source_event_id)
      "development-artifact-relations-source:#{source_event_id}"
    end

    def failure_command(command_id)
      "development-artifact-relations-failure-command:#{command_id}"
    end

    def call(command_id:, artifact_id:, source_event_id: nil)
      markers = [ "development-artifact:#{artifact_id}", "command:#{command_id}" ]
      markers << source(source_event_id) if source_event_id
      markers
    end
  end
end
