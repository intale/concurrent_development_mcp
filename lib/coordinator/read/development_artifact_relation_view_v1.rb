# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelationViewV1 < Value
    attribute :relation_id, Types::DevelopmentArtifactRelationId
    attribute :source_artifact_id, Types::DevelopmentArtifactId
    attribute :relation, Types::DevelopmentArtifactRelationKind
    attribute :target, Coordinator::Write::DevelopmentArtifacts::RelationTargetV1
    attribute :attributes, Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1
    attribute :declared, DevelopmentArtifactEventEvidenceV1

    def relation_attributes
      self[:attributes]
    end
  end
end
