# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactSourceStateV1 < Value
      attribute :legacy_artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :source, DevelopmentArtifacts::SourceV1
      attribute :content, DevelopmentArtifacts::ArtifactV2::Content
      attribute :created_origin, DevelopmentArtifactPropertyOriginV1
      attribute :scope_origin, DevelopmentArtifactPropertyOriginV1
      attribute :title_origin, DevelopmentArtifactPropertyOriginV1
      attribute :kind_origin, DevelopmentArtifactPropertyOriginV1
      attribute :source_origin, DevelopmentArtifactPropertyOriginV1
      attribute :content_origin, DevelopmentArtifactPropertyOriginV1
      attribute :labels, Types::Array.of(DevelopmentArtifactLabelStateV1)
    end
  end
end
