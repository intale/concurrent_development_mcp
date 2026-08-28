# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactGetQueryV1 < Value
    attribute :artifact_id, Types::DevelopmentArtifactId
    attribute? :observation_id, Types::DevelopmentArtifactObservationId.optional
  end
end
