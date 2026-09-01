# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectRepositoryType < BaseObject
    graphql_name "ProjectRepository"
    description "One latest available registered Repository member of an exact Project scope."

    field :id, ID, null: false, method: :repository_id
    field :display_name, String, null: true
    field :paths, [ String ], null: false
    field :remotes, [ String ], null: false
    field :registered_at, String, null: false
  end
end
