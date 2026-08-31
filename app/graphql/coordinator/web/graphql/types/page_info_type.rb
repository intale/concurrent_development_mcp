# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class PageInfoType < BaseObject
    graphql_name "PageInfo"
    description "Opaque forward-pagination state for one bounded read-model window."

    field :end_cursor, String, null: true
    field :has_next_page, Boolean, null: false
  end
end
