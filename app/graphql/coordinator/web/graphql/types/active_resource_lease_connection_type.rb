# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ActiveResourceLeaseConnectionType < BaseObject
    graphql_name "ActiveResourceLeaseConnection"

    field :as_of, String, null: false
    field :nodes, [ ActiveResourceLeaseType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
