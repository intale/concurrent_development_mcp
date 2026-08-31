# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationChangeSetType < BaseObject
    graphql_name "CoordinationChangeSet"

    field :acceptance_criteria, [ String ], null: false
    field :domain_status, String, null: false
    field :goal, String, null: false
    field :id, ID, null: false, method: :change_set_id
    field :last_processed_at, String, null: false
    field :open_work_item_count, Integer, null: false
    field :running_work_item_count, Integer, null: false
    field :work_item_count, Integer, null: false
  end
end
