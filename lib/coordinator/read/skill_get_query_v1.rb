# frozen_string_literal: true

module Coordinator::Read
  class SkillGetQueryV1 < Value
    attribute :name, Types::SkillName
    attribute :scope, Types::SkillScope
  end
end
