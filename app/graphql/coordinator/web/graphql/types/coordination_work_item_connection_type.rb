# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationWorkItemConnectionType < BaseObject
    graphql_name "CoordinationWorkItemConnection"

    field :nodes, [ CoordinationWorkItemType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
