# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectSortEnum < BaseEnum
    graphql_name "ProjectSort"

    value "SCOPE_ASC", value: "scope_asc", description: "Exact Project scope ascending."
    value "SCOPE_DESC", value: "scope_desc", description: "Exact Project scope descending."
  end
end
