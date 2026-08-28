# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ObservationBuilder
      def initialize(identity_builder: ObservationIdentityBuilder.new)
        @identity_builder = identity_builder
      end

      def call(artifact:)
        ArtifactObservationV1.new(
          observation_id: @identity_builder.call(
            artifact_id: artifact.artifact_id,
            scope: artifact.scope,
            source: artifact.source
          ),
          artifact_id: artifact.artifact_id,
          scope: artifact.scope,
          title: artifact.title,
          kind: artifact.kind,
          labels: artifact.labels,
          source: artifact.source
        )
      end
    end
  end
end
