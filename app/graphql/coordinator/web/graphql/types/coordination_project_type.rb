# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationProjectType < BaseObject
    graphql_name "CoordinationProject"

    field :id, ID, null: false, method: :repository_id
    field :name, String, null: true, method: :display_name
    field :scope, String, null: false
  end
end
