# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectKnowledgeType < BaseObject
    graphql_name "ProjectKnowledge"

    field :artifacts, DevelopmentArtifactConnectionType, null: false, connection: false
    field :project, CoordinationProjectType, null: false
    field :skills, SkillConnectionType, null: false, connection: false
  end
end
