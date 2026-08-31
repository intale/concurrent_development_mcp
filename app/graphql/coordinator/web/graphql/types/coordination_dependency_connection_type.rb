# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationDependencyConnectionType < BaseObject
    graphql_name "CoordinationDependencyConnection"

    field :nodes, [ CoordinationDependencyType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
