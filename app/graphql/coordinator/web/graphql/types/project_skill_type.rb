# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectSkillType < BaseObject
    graphql_name "ProjectSkill"

    field :project, CoordinationProjectType, null: false
    field :skill, SkillType, null: false
  end
end
