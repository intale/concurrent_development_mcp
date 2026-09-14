# frozen_string_literal: true

module Coordinator::Read
  class SkillListQueryV1 < Value
    attribute :name, Types::SkillName.optional
    attribute :scope, Types::SkillScope.optional
    attribute :after_updated_at, Types::String.optional
    attribute :after_skill_id, ProjectedSkillId.optional
    attribute :order, Types::String.default("skill_id".freeze).enum("skill_id", "updated_at")
    attribute :sort, Types::String.default("newest_first".freeze).enum("newest_first", "oldest_first")
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
  end
end
