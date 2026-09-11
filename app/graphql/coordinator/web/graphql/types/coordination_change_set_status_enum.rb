# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationChangeSetStatusEnum < BaseEnum
    graphql_name "CoordinationChangeSetStatus"
    description "Current projected ChangeSet lifecycle status."

    value "PLANNING", value: "planning"
    value "ACTIVE", value: "active"
    value "COMPLETED", value: "completed"
  end
end
