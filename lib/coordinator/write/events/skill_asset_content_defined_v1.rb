# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillAssetContentDefinedV1 < Base
      contract type: "SkillAssetContentDefined", version: 1

      attribute :asset_id, Types::UuidV7
      # UTF-8 text is stored directly. Binary content uses canonical Base64,
      # and its representation is described by the event metadata.
      attribute :content, Types::ContentText | Types::ContentBase64
    end
  end
end
