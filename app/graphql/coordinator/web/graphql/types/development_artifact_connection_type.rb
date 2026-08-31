# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactConnectionType < BaseObject
    graphql_name "DevelopmentArtifactConnection"

    field :nodes, [ DevelopmentArtifactSummaryType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
