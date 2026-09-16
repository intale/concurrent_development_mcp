# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module LegacyDevelopmentArtifacts
      class ArtifactV2 < Value
        Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

        attribute :artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
        attribute :scope, Types::DevelopmentArtifactScope
        attribute :title, Types::DevelopmentArtifactTitle
        attribute :kind, Types::DevelopmentArtifactKind
        attribute :labels, Types::DevelopmentArtifactLabels
        attribute :content, Content
        attribute :source, DevelopmentArtifacts::SourceV1
      end

      class ArtifactObservationV1 < Value
        attribute :observation_id, LegacyDevelopmentArtifactTypes::ObservationId
        attribute :artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
        attribute :scope, Types::DevelopmentArtifactScope
        attribute :title, Types::DevelopmentArtifactTitle
        attribute :kind, Types::DevelopmentArtifactKind
        attribute :labels, Types::DevelopmentArtifactLabels
        attribute :source, DevelopmentArtifacts::SourceV1
      end

      class RelationV1 < Value
        attribute :relation_id, LegacyDevelopmentArtifactTypes::RelationId
        attribute :source_artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
        attribute :relation, Types::DevelopmentArtifactRelationKind
        attribute :target, DevelopmentArtifacts::RelationTargetV1
        attribute :attributes, DevelopmentArtifacts::RelationAttributesV1

        def relation_attributes
          self[:attributes]
        end
      end
    end
  end
end
