# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillAssetExecutabilityDefinedV1 < Base
      contract type: "SkillAssetExecutabilityDefined", version: 1

      attribute :asset_id, Types::UuidV7
      attribute :executable, Types::Bool
    end
  end
end
