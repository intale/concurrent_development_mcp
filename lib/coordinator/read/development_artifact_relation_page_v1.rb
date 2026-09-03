# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelationPageV1 < Value
    class Cursor < Value
      attribute :after_observed_sequence, Types::Integer.constrained(gteq: 0)
      attribute :through_observed_sequence, Types::Integer.constrained(gteq: 0).optional
      attribute :after_declared_global_position, Types::GlobalPosition.optional
      attribute :after_relation_id, ProjectedDevelopmentArtifactRelationId.optional
    end

    attribute :artifact, DevelopmentArtifactSummaryV1.optional
    attribute :items,
              Types::Array.of(DevelopmentArtifactRelationViewV1).constrained(
                max_size: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
              )
    attribute :continuation_cursor, Cursor
    attribute :has_more, Types::Bool
  end
end
