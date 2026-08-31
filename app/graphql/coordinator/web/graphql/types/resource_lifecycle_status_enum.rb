# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceLifecycleStatusEnum < BaseEnum
    graphql_name "ResourceLifecycleStatus"

    value "CURRENT", value: "current"
    value "INACTIVE", value: "inactive"
    value "REGISTERED", value: "registered"
  end
end
