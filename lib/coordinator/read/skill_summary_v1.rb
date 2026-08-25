# frozen_string_literal: true

module Coordinator::Read
  class SkillSummaryV1 < Value
    attribute :skill_id, Types::SkillId
    attribute :name, Types::SkillName
    attribute :scope, Types::SkillScope
    attribute :revision, Types::SkillRevision
    attribute :description, Types::SkillDescription
    attribute :content_digest, Types::Sha256Digest
    attribute :asset_count,
              Types::Integer.constrained(gteq: 0, lteq: Types::SKILL_ASSET_MAXIMUM_COUNT)
    attribute :published, SkillSourceEvidenceV1
  end
end
