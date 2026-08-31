# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ActiveResourceLeaseType < BaseObject
    graphql_name "ActiveResourceLease"

    field :agent_id, String, null: false
    field :attempt_id, ID, null: false
    field :base_blob_oid, String, null: true
    field :change_set_id, ID, null: false
    field :expires_at, String, null: false
    field :fencing_token, String, null: false
    field :id, ID, null: false, method: :lease_id
    field :last_expanded_at, String, null: true
    field :last_expanded_event_id, ID, null: true
    field :last_projected_at, String, null: false
    field :last_renewed_at, String, null: true
    field :last_renewed_event_id, ID, null: true
    field :lease_set_id, ID, null: false
    field :policy_version, String, null: false
    field :previous_expires_at, String, null: true
    field :reserved_at, String, null: false
    field :reserved_event_id, ID, null: false
    field :resource_id, ID, null: false
    field :resource_kind, ResourceKindEnum, null: false
    field :resource_lifecycle_status, ResourceLifecycleStatusEnum, null: true
    field :resource_path, String, null: false
    field :work_item_id, ID, null: false

    def fencing_token
      object.fencing_token.to_s
    end
  end
end
