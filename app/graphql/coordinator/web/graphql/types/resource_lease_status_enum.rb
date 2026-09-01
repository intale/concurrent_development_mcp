# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceLeaseStatusEnum < BaseEnum
    graphql_name "ResourceLeaseStatus"

    value "ACTIVE", value: "active"
    value "EXPIRED", value: "expired"
    value "RELEASED", value: "released"
    value "ATTEMPT_TERMINAL", value: "attempt_terminal"
  end
end
