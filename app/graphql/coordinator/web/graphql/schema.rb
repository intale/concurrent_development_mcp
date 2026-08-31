# frozen_string_literal: true

module Coordinator::Web::Graphql
  class Schema < GraphQL::Schema
    query Types::QueryType

    max_depth 8
    max_complexity 100
  end
end
