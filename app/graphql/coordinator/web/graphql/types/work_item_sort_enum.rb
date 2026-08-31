# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class WorkItemSortEnum < BaseEnum
    graphql_name "WorkItemSort"

    value "WORK_ITEM_ID_ASC", value: "work_item_id_asc"
    value "STATUS_ASC", value: "status_asc"
    value "LATEST_ACTIVITY_DESC", value: "latest_activity_desc"
  end
end
