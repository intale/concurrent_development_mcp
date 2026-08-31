# frozen_string_literal: true

module Coordinator::Read::Web
  class KnowledgeBrowserV1
    class Project < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :scope, Coordinator::Shared::Types::String
      attribute :display_name, Coordinator::Shared::Types::String.optional
    end

    class Catalog < Coordinator::Shared::Value
      attribute :project, Project
      attribute :skills, Coordinator::Read::SkillPageV1
      attribute :artifacts, Coordinator::Read::DevelopmentArtifactPageV1
    end

    class SkillDetail < Coordinator::Shared::Value
      attribute :project, Project
      attribute :skill, Coordinator::Read::SkillViewV1
    end

    class SkillAssetDetail < Coordinator::Shared::Value
      Asset = Coordinator::Shared::Types.Instance(Coordinator::Read::SkillTextAssetViewV2) |
        Coordinator::Shared::Types.Instance(Coordinator::Read::SkillBinaryAssetViewV2)

      attribute :project, Project
      attribute :asset, Asset
    end

    class ArtifactDetail < Coordinator::Shared::Value
      Content = Coordinator::Shared::Types.Instance(Coordinator::Read::DevelopmentArtifactTextContentViewV2) |
        Coordinator::Shared::Types.Instance(Coordinator::Read::DevelopmentArtifactBinaryContentViewV2)

      attribute :project, Project
      attribute :artifact, Coordinator::Read::DevelopmentArtifactSummaryV1
      attribute :content, Content
      attribute :relationships, Coordinator::Read::DevelopmentArtifactRelationPageV1
    end
  end
end
