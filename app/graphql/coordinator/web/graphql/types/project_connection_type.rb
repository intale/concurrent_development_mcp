# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectConnectionType < BaseObject
    graphql_name "ProjectConnection"
    description "A bounded page of projects and its opaque continuation state."

    field :nodes, [ ProjectType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
