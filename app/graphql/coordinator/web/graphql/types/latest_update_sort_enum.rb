# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class LatestUpdateSortEnum < BaseEnum
    graphql_name "LatestUpdateSort"
    description "Stable ordering by the latest projected event timestamp and entity identifier."

    value "NEWEST_FIRST", value: "newest_first"
    value "OLDEST_FIRST", value: "oldest_first"
  end
end
