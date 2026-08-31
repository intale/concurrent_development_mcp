# frozen_string_literal: true

module Coordinator::Read::Web
  class KnowledgeBrowserQueryV1
    class Catalog < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :skill_name, Coordinator::Shared::Types::SkillName.optional
      attribute :after_skill_id, Coordinator::Shared::Types::SkillId.optional
      attribute :artifact_kind, Coordinator::Shared::Types::DevelopmentArtifactKind.optional
      attribute :artifact_labels, Coordinator::Shared::Types::DevelopmentArtifactLabels
      attribute :artifact_source_kind,
                Coordinator::Shared::Types::DevelopmentArtifactSourceKind.optional
      attribute :after_artifact_global_position,
                Coordinator::Shared::Types::GlobalPosition.optional
    end

    class Skill < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :name, Coordinator::Shared::Types::SkillName
    end

    class SkillAsset < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :name, Coordinator::Shared::Types::SkillName
      attribute :path, Coordinator::Shared::Types::SkillAssetPath
    end

    class Artifact < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :artifact_id, Coordinator::Shared::Types::DevelopmentArtifactId
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :direction,
                Coordinator::Shared::Types::String.enum("incoming", "outgoing", "both")
      attribute :relation,
                Coordinator::Shared::Types::DevelopmentArtifactRelationKind.optional
      attribute :cursor, Coordinator::Read::DevelopmentArtifactRelationPageV1::Cursor
    end
  end
end
