# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationDependencyType < BaseObject
    graphql_name "CoordinationDependency"

    field :blocking, Boolean, null: false
    field :consumer_repository_id, ID, null: true
    field :consumer_work_item_id, ID, null: false
    field :declared_at, String, null: false
    field :dependency_kind, String, null: false
    field :id, ID, null: false, method: :dependency_id
    field :last_processed_at, String, null: false
    field :producer_repository_id, ID, null: true
    field :producer_work_item_id, ID, null: false
    field :satisfied_at, String, null: true
  end
end
