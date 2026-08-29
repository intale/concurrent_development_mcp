# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class AssetV2 < Value
      Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

      attribute :path, Types::SkillAssetPath
      attribute :executable, Types::Bool
      attribute :content, Content

      def media_type
        content.media_type
      end

      def content_sha256
        content.content_sha256
      end

      def byte_size
        content.byte_size
      end
    end
  end
end
