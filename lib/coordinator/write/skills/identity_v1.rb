# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class IdentityV1 < Value
      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
    end
  end
end
