# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactGetQueryV1 < Value
    attribute :artifact_id, Types::DevelopmentArtifactId
  end
end
