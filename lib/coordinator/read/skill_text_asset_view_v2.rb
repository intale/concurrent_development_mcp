# frozen_string_literal: true

module Coordinator::Read
  class SkillTextAssetViewV2 < Value
    attribute :skill_id, Types::SkillId
    attribute :name, Types::SkillName
    attribute :scope, Types::SkillScope
    attribute :revision, Types::SkillRevision
    attribute :path, Types::SkillAssetPath
    attribute :encoding, Types::String.enum("utf-8")
    attribute :media_type, Types::SkillAssetMediaType
    attribute :executable, Types::Bool
    attribute :text, Types::ContentText
    attribute :content_sha256, Types::Sha256Digest
    attribute :byte_size, Types::SkillAssetByteSize
    attribute :published, SkillSourceEvidenceV1
  end
end
