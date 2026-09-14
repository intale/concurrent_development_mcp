# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceWorkIntentionModeEnum < BaseEnum
    graphql_name "ResourceWorkIntentionMode"

    value "SHARED", value: "shared"
    value "EXCLUSIVE", value: "exclusive"
  end
end
