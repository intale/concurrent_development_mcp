# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectSortEnum < BaseEnum
    graphql_name "ProjectSort"

    value "NEWEST_FIRST", value: "newest_first", description: "Most recently updated Project first."
    value "OLDEST_FIRST", value: "oldest_first", description: "Least recently updated Project first."
  end
end
