# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationPresentationStatusEnum < BaseEnum
    graphql_name "CoordinationPresentationStatus"

    value "PENDING", value: "pending"
    value "READY", value: "ready"
    value "ASSIGNED", value: "assigned"
    value "RUNNING", value: "running"
    value "COMPLETED", value: "completed"
  end
end
