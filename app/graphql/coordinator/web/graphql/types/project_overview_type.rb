# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectOverviewType < BaseObject
    graphql_name "ProjectOverview"
    description "Latest available overview of one exact Project scope and its Repository members."

    field :project_ref, ID, null: false
    field :scope, String, null: false
    field :display_label, String, null: false
    field :repository_count, Integer, null: false
    field :repositories, ProjectRepositoryConnectionType, null: false, connection: false
  end
end
