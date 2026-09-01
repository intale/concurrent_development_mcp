# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceLeaseConnectionType < BaseObject
    graphql_name "ResourceLeaseConnection"

    field :as_of, String, null: false
    field :nodes, [ ResourceLeaseType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
