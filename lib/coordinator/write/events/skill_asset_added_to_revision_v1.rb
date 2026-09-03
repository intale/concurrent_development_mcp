# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillAssetAddedToRevisionV1 < Base
      contract type: "SkillAssetAddedToRevision", version: 1

      attribute :skill_revision_id, Types::UuidV7
      attribute :skill_id, Types::SkillId
      attribute :revision, Types::SkillRevision
      attribute :asset_id, Types::UuidV7
    end
  end
end
