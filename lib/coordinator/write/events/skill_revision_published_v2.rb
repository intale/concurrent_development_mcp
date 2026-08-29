# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillRevisionPublishedV2 < Base
      contract type: "SkillRevisionPublished", version: 2
      Asset = Skills::AssetV2

      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :revision, Types::SkillRevision
      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets,
                Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
      attribute :content_digest, Types::Sha256Digest
      attribute :published_at, Types::Timestamp
    end
  end
end
