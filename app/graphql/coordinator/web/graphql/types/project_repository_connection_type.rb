# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectRepositoryConnectionType < BaseObject
    graphql_name "ProjectRepositoryConnection"
    description "A bounded page of explicit Repository members for one Project."

    field :nodes, [ ProjectRepositoryType ], null: false
    field :page_info, PageInfoType, null: false
    field :total_count, Integer, null: false
  end
end
