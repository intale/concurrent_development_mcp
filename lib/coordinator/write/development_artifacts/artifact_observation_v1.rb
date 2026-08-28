# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ArtifactObservationV1 < Value
      attribute :observation_id, Types::DevelopmentArtifactObservationId
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :source, SourceV1
    end
  end
end
