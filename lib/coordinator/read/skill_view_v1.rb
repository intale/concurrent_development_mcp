# frozen_string_literal: true

module Coordinator::Read
  class SkillViewV1 < Value
    Asset = SkillAssetManifestV1

    attribute :skill_id, ProjectedSkillId
    attribute :name, Types::SkillName
    attribute :scope, Types::SkillScope
    attribute :revision, Types::SkillRevision
    attribute :description, Types::SkillDescription
    attribute :instructions, Types::SkillInstructions
    attribute :assets, Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
    attribute :content_digest, Types::Sha256Digest
    attribute :published, SkillSourceEvidenceV1
  end
end
