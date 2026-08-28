# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ObservationIdentityDocumentV1 < Value
      SCHEMA = "development-artifact-observation-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :source_kind, Types::DevelopmentArtifactSourceKind
      attribute :source_locator, Types::DevelopmentArtifactSourceLocator
      attribute :source_revision, Types::DevelopmentArtifactSourceRevision.optional
      attribute :source_observed_at, Types::Timestamp
      attribute :source_collector, Types::DevelopmentArtifactCollector
    end
  end
end
