# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactRelationConnectionType < BaseObject
    graphql_name "DevelopmentArtifactRelationConnection"

    field :nodes, [ DevelopmentArtifactRelationType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
