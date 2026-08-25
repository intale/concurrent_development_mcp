# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class AssetV1 < Value
      attribute :path, Types::SkillAssetPath
      attribute :media_type, Types::SkillAssetMediaType
      attribute :executable, Types::Bool
      attribute :content_base64, Types::SkillAssetContentBase64
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::SkillAssetByteSize
    end
  end
end
