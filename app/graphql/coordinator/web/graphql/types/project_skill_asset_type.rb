# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectSkillAssetType < BaseObject
    graphql_name "ProjectSkillAsset"

    field :asset, SkillAssetContentType, null: false
    field :project, CoordinationProjectType, null: false
  end
end
