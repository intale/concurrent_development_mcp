# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillAssetCreatedV1 < Base
      contract type: "SkillAssetCreated", version: 1

      attribute :asset_id, Types::UuidV7
    end
  end
end
