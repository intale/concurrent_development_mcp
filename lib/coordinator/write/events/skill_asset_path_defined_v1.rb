# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillAssetPathDefinedV1 < Base
      contract type: "SkillAssetPathDefined", version: 1

      attribute :asset_id, Types::UuidV7
      attribute :path, Types::SkillAssetPath
    end
  end
end
