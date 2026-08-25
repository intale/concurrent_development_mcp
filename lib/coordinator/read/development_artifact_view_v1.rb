# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactViewV1 < Value
    attribute :artifact, DevelopmentArtifactSummaryV1
    attribute :relationships,
              Types::Array.of(DevelopmentArtifactRelationViewV1).constrained(
                max_size: Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT
              )
  end
end
