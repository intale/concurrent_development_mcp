# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectType < BaseObject
    graphql_name "Project"
    description "One latest available projected repository registration in an exact project scope."

    field :id, ID, null: false, method: :repository_id
    field :scope, String, null: false
    field :name, String, null: true, method: :display_name
    field :paths, [ String ], null: false
    field :remotes, [ String ], null: false
    field :registered_at, String, null: false

    def registered_at
      object.registered.occurred_at
    end
  end
end
