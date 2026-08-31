# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectResourcesType < BaseObject
    graphql_name "ProjectResources"

    field :active_leases, ActiveResourceLeaseConnectionType, null: false, connection: false
    field :project, CoordinationProjectType, null: false
    field :resources, ProjectResourceConnectionType, null: false, connection: false
  end
end
