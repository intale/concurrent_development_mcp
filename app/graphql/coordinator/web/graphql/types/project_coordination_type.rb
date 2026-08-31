# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectCoordinationType < BaseObject
    graphql_name "ProjectCoordination"

    field :change_sets, CoordinationChangeSetConnectionType, null: false, connection: false
    field :dependencies, CoordinationDependencyConnectionType, null: false, connection: false
    field :project, CoordinationProjectType, null: false
    field :work_items, CoordinationWorkItemConnectionType, null: false, connection: false
  end
end
