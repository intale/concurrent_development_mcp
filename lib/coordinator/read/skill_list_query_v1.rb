# frozen_string_literal: true

module Coordinator::Read
  class SkillListQueryV1 < Value
    attribute :name, Types::SkillName.optional
    attribute :scope, Types::SkillScope.optional
    attribute :after_skill_id, Types::SkillId.optional
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
  end
end
