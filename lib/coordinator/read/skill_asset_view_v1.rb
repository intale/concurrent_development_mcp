# frozen_string_literal: true

module Coordinator::Read
  class SkillAssetViewV1 < Value
    attribute :skill_id, Types::SkillId
    attribute :name, Types::SkillName
    attribute :scope, Types::SkillScope
    attribute :revision, Types::SkillRevision
    attribute :path, Types::SkillAssetPath
    attribute :media_type, Types::SkillAssetMediaType
    attribute :executable, Types::Bool
    attribute :content_base64, Types::SkillAssetContentBase64
    attribute :content_sha256, Types::Sha256Digest
    attribute :byte_size, Types::SkillAssetByteSize
    attribute :published, SkillSourceEvidenceV1
  end
end
