# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectResourceConnectionType < BaseObject
    graphql_name "ProjectResourceConnection"

    field :nodes, [ ProjectResourceType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
