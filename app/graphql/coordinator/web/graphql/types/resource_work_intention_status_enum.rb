# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceWorkIntentionStatusEnum < BaseEnum
    graphql_name "ResourceWorkIntentionStatus"

    value "ACTIVE", value: "active"
    value "EXPIRED", value: "expired"
    value "WITHDRAWN", value: "withdrawn"
    value "ATTEMPT_TERMINAL", value: "attempt_terminal"
  end
end
