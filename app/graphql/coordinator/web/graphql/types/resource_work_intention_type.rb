# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceWorkIntentionType < BaseObject
    graphql_name "ResourceWorkIntention"

    field :agent_id, String, null: false
    field :attempt_id, ID, null: false
    field :attempt_terminal_at, String, null: true
    field :attempt_terminal_event_id, ID, null: true
    field :base_blob_oid, String, null: true
    field :change_set_id, ID, null: false
    field :context, String, null: true, resolver_method: :work_context
    field :declared_at, String, null: false
    field :declared_event_id, ID, null: false
    field :expires_at, String, null: false
    field :fencing_token, String, null: false
    field :id, ID, null: false, method: :intention_id
    field :intention_set_id, ID, null: false
    field :last_expanded_at, String, null: true
    field :last_expanded_event_id, ID, null: true
    field :last_renewed_at, String, null: true
    field :last_renewed_event_id, ID, null: true
    field :mode, ResourceWorkIntentionModeEnum, null: false
    field :policy_version, String, null: false
    field :previous_expires_at, String, null: true
    field :purpose, String, null: false
    field :repository_id, ID, null: false
    field :resource_id, ID, null: false
    field :resource_kind, ResourceKindEnum, null: false
    field :resource_lifecycle_status, ResourceLifecycleStatusEnum, null: true
    field :resource_path, String, null: false
    field :status, ResourceWorkIntentionStatusEnum, null: false
    field :updated_at, String, null: false
    field :withdrawal_event_id, ID, null: true
    field :withdrawn_at, String, null: true
    field :work_item_id, ID, null: false

    def fencing_token
      object.fencing_token.to_s
    end

    def work_context
      object.context
    end
  end
end
