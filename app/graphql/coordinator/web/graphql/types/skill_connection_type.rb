# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class SkillConnectionType < BaseObject
    graphql_name "SkillConnection"

    field :nodes, [ SkillSummaryType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
