# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillRevisionPublishedV3 < Base
      contract type: "SkillRevisionPublished", version: 3

      attribute :skill_id, Types::SkillId
      attribute :skill_revision_id, Types::UuidV7
      attribute :revision, Types::SkillRevision
    end
  end
end
