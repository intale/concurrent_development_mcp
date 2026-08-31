# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationChangeSetConnectionType < BaseObject
    graphql_name "CoordinationChangeSetConnection"

    field :nodes, [ CoordinationChangeSetType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
