# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectResourceType < BaseObject
    graphql_name "ProjectResource"

    field :id, ID, null: false, method: :resource_id
    field :kind, ResourceKindEnum, null: false
    field :latest_transition_actor_id, String, null: true
    field :last_transition_at, String, null: true
    field :latest_transition_event_id, ID, null: true
    field :lifecycle_status, ResourceLifecycleStatusEnum, null: false
    field :path, String, null: false
    field :registered_actor_id, String, null: true
    field :registered_at, String, null: true
    field :registered_event_id, ID, null: true
    field :repository_id, ID, null: false
    field :unbinding_reason, String, null: true
  end
end
