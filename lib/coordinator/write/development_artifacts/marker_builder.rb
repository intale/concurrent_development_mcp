# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class MarkerBuilder
      def capture(artifact_id:, command_id:)
        [ "development-artifact:#{artifact_id}", "command:#{command_id}" ].freeze
      end

      def relation(artifact_relation:, command_id:)
        [
          "development-artifact:#{artifact_relation.source_artifact_id}",
          "development-artifact-relation:#{artifact_relation.relation_id}",
          "command:#{command_id}"
        ].freeze
      end
    end
  end
end
