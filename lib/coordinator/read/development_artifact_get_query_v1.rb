# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactGetQueryV1 < Value
    attribute :artifact_id, ProjectedDevelopmentArtifactId
    attribute? :observation_id, ProjectedDevelopmentArtifactObservationId.optional
  end
end
