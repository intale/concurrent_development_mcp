# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillRevisionCreatedV1 < Base
      contract type: "SkillRevisionCreated", version: 1

      attribute :skill_revision_id, Types::UuidV7
      attribute :skill_id, Types::SkillId
      attribute :revision, Types::SkillRevision
    end
  end
end
