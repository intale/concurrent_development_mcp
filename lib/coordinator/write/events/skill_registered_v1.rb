# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillRegisteredV1 < Base
      contract type: "SkillRegistered", version: 1

      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
    end
  end
end
