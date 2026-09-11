# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class WorkItemSortEnum < BaseEnum
    graphql_name "WorkItemSort"

    value "UPDATED_AT_DESC", value: "updated_at_desc"
    value "UPDATED_AT_ASC", value: "updated_at_asc"
    value "STATUS_ASC", value: "status_asc"
    value "LATEST_ACTIVITY_DESC", value: "latest_activity_desc"
  end
end
