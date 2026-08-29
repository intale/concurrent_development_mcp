# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class MarkerBuilder
      def capture(event:, command_id:)
        markers = [ "command:#{command_id}" ]
        case event
        when Events::DevelopmentArtifactCapturedV1, Events::DevelopmentArtifactCapturedV2
          markers << "development-artifact:#{event.artifact.artifact_id}"
        when Events::DevelopmentArtifactObservedV1
          markers << "development-artifact:#{event.observation.artifact_id}"
          markers << "development-artifact-observation:#{event.observation.observation_id}"
        else
          raise "Unexpected Development Artifact capture event #{event.class.name}"
        end
        markers.freeze
      end

      def classification(event:, command_id:)
        [
          "development-artifact:#{event.artifact_id}",
          "development-artifact-observation:#{event.observation_id}",
          "command:#{command_id}"
        ].freeze
      end

      def relation(artifact_relation:, command_id:)
        [
          "development-artifact:#{artifact_relation.source_artifact_id}",
          "development-artifact-relation:#{artifact_relation.relation_id}",
          "command:#{command_id}"
        ].freeze
      end

      def supersession(event:, command_id:)
        [
          "development-artifact:#{event.source_artifact_id}",
          "development-artifact-relation:#{event.superseded_relation_id}",
          "development-artifact-relation:#{event.replacement_relation_id}",
          "command:#{command_id}"
        ].freeze
      end
    end
  end
end
