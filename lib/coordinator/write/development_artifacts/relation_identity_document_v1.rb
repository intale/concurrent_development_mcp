# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationIdentityDocumentV1 < Value
      SCHEMA = "development-artifact-relation-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute :relation, Types::DevelopmentArtifactRelationKind
      attribute :target, RelationTargetV1
      attribute :attributes, RelationAttributesV1
    end
  end
end
