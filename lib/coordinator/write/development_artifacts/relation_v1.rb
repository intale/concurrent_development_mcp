# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationV1 < Value
      attribute :relation_id, Types::DevelopmentArtifactRelationId
      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute :relation, Types::DevelopmentArtifactRelationKind
      attribute :target, RelationTargetV1
      attribute :attributes, RelationAttributesV1

      def relation_attributes
        self[:attributes]
      end

      def with_target(target)
        self.class.new(to_h.merge(target:))
      end
    end
  end
end
