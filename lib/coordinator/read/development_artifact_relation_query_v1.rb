# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelationQueryV1 < Value
    attribute :artifact_id, Types::DevelopmentArtifactId
    attribute :direction, Types::String.enum("incoming", "outgoing", "both")
    attribute :relation, Types::DevelopmentArtifactRelationKind.optional
    attribute :include_superseded, Types::Bool
    attribute :cursor, DevelopmentArtifactRelationPageV1::Cursor
    attribute :limit,
              Types::Integer.constrained(
                gteq: 1,
                lteq: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
              )
  end
end
