# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationWorkItemType < BaseObject
    graphql_name "CoordinationWorkItem"

    field :acceptance_criteria, [ String ], null: false
    field :active_agent_id, String, null: true
    field :active_attempt_id, String, null: true
    field :acquired_at, String, null: true
    field :attempt_authorized_at, String, null: true
    field :attempt_started_at, String, null: true
    field :attempt_status, String, null: true
    field :attempt_terminal_at, String, null: true
    field :change_set_id, ID, null: false
    field :competitive_mode, Boolean, null: false
    field :completed_at, String, null: true
    field :created_at, String, null: false
    field :domain_status, String, null: false
    field :goal, String, null: false
    field :id, ID, null: false, method: :work_item_id
    field :last_processed_at, String, null: false
    field :made_ready_at, String, null: true
    field :presentation_status, CoordinationPresentationStatusEnum, null: false
    field :repository_id, ID, null: false
  end
end
