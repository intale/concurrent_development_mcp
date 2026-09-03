# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactRelationDeclaredV2 < Base
      contract type: "DevelopmentArtifactRelationDeclared", version: 2

      attribute :relation_id, Types::DevelopmentArtifactRelationId
      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute :relation, Types::DevelopmentArtifactRelationKind
      attribute :target_kind, Types::DevelopmentArtifactTargetKind
      attribute :target_id, Types::DevelopmentArtifactTargetId
      attribute :path, Types::DevelopmentArtifactRelationPath.optional
      attribute? :fragment, Types::DevelopmentArtifactRelationFragment.optional
      attribute? :normalized_locator, Types::DevelopmentArtifactSourceLocator.optional
    end
  end
end
