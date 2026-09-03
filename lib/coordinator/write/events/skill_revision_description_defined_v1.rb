# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillRevisionDescriptionDefinedV1 < Base
      contract type: "SkillRevisionDescriptionDefined", version: 1

      attribute :skill_revision_id, Types::UuidV7
      attribute :description, Types::SkillDescription
    end
  end
end
