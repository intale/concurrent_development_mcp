# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceWorkIntentionConnectionType < BaseObject
    graphql_name "ResourceWorkIntentionConnection"

    field :as_of, String, null: false
    field :nodes, [ ResourceWorkIntentionType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
