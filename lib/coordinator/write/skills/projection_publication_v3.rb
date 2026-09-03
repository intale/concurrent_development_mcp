# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class ProjectionPublicationV3 < Value
      Asset = Types.Instance(AssetV2)

      attribute :skill_id, Types::SkillId
      attribute :skill_revision_id, Types::UuidV7
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :revision, Types::SkillRevision
      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets, Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
      attribute :content_digest, Types::Sha256Digest
      attribute :published_at, Types::Timestamp
    end
  end
end
