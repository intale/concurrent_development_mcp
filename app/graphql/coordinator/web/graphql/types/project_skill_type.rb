# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectSkillType < BaseObject
    graphql_name "ProjectSkill"

    field :skill, SkillType, null: false
  end
end
