# frozen_string_literal: true

module Coordinator::Read::Web
  class KnowledgeBrowserQueryV1
    class Skills < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :name, Coordinator::Shared::Types::SkillName.optional
      attribute :after_skill_id, Coordinator::Read::ProjectedSkillId.optional
    end

    class Artifacts < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :kind, Coordinator::Shared::Types::DevelopmentArtifactKind.optional
      attribute :labels, Coordinator::Shared::Types::DevelopmentArtifactLabels
      attribute :source_kind, Coordinator::Shared::Types::DevelopmentArtifactSourceKind.optional
      attribute :after_global_position, Coordinator::Shared::Types::GlobalPosition.optional
    end

    class Skill < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :name, Coordinator::Shared::Types::SkillName
    end

    class SkillAsset < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :name, Coordinator::Shared::Types::SkillName
      attribute :path, Coordinator::Shared::Types::SkillAssetPath
    end

    class Artifact < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :artifact_id, Coordinator::Read::ProjectedDevelopmentArtifactId
    end

    class Relationships < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :artifact_id, Coordinator::Read::ProjectedDevelopmentArtifactId
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :direction, Coordinator::Shared::Types::String.enum("incoming", "outgoing", "both")
      attribute :relation, Coordinator::Shared::Types::DevelopmentArtifactRelationKind.optional
      attribute :cursor, Coordinator::Read::DevelopmentArtifactRelationPageV1::Cursor
    end
  end
end
