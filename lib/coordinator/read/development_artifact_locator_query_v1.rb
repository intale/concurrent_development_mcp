# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactLocatorQueryV1 < Value
    attribute :scope, Types::DevelopmentArtifactScope
    attribute :source_kind, Types::DevelopmentArtifactSourceKind
    attribute :locator, Types::DevelopmentArtifactSourceLocator
    attribute :source_revision, Types::DevelopmentArtifactSourceRevision.optional
    attribute :revision_specified, Types::Bool
    attribute :cursor, DevelopmentArtifactLocatorPageV1::Cursor
    attribute :limit,
              Types::Integer.constrained(
                gteq: 1,
                lteq: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
              )
  end
end
