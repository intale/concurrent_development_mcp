# frozen_string_literal: true

module Coordinator::Read::Web
  class KnowledgeBrowserV1
    class SkillDetail < Coordinator::Shared::Value
      attribute :skill, Coordinator::Read::SkillViewV1
    end

    class SkillAssetDetail < Coordinator::Shared::Value
      Asset = Coordinator::Shared::Types.Instance(Coordinator::Read::SkillTextAssetViewV2) |
        Coordinator::Shared::Types.Instance(Coordinator::Read::SkillBinaryAssetViewV2)

      attribute :asset, Asset
    end

    class ArtifactDetail < Coordinator::Shared::Value
      Content = Coordinator::Shared::Types.Instance(Coordinator::Read::DevelopmentArtifactTextContentViewV2) |
        Coordinator::Shared::Types.Instance(Coordinator::Read::DevelopmentArtifactBinaryContentViewV2)

      attribute :artifact, Coordinator::Read::DevelopmentArtifactSummaryV1
      attribute :content, Content
    end

    class ArtifactRelationships < Coordinator::Shared::Value
      attribute :artifact, Coordinator::Read::DevelopmentArtifactSummaryV1
      attribute :relationships, Coordinator::Read::DevelopmentArtifactRelationPageV1
    end
  end
end
