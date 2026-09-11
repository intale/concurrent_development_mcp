# frozen_string_literal: true

module Coordinator::Read
  class SkillPageV1 < Value
    attribute :items, Types::Array.of(SkillSummaryV1).constrained(max_size: 100)
    attribute :next_updated_at, Types::String.optional
    attribute :next_skill_id, ProjectedSkillId.optional
    attribute :has_more, Types::Bool
  end
end
