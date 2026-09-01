# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class CoordinationBaseSnapshotType < BaseObject
    graphql_name "CoordinationBaseSnapshot"

    field :commit_oid, String, null: false
    field :object_format, String, null: false
    field :repository_id, ID, null: false
  end

  class CoordinationAttemptType < BaseObject
    graphql_name "CoordinationAttempt"

    field :abandonment_reason, String, null: true
    field :agent_id, String, null: false
    field :authorized_at, String, null: false
    field :base_snapshots, [ CoordinationBaseSnapshotType ], null: false
    field :id, ID, null: false, method: :attempt_id
    field :selected_candidate_id, ID, null: true
    field :started_at, String, null: true
    field :status, String, null: false
    field :terminal_at, String, null: true
  end

  class CoordinationCheckpointType < BaseObject
    graphql_name "CoordinationCheckpoint"

    field :checkpoint_kind, String, null: false
    field :evidence_status, String, null: false
    field :head_commit_oid, String, null: false
    field :id, ID, null: false, method: :candidate_id
    field :manifest_digest, String, null: false
    field :submitted_at, String, null: false
    field :target_branch, String, null: false
  end

  class ProjectCoordinationType < BaseObject
    graphql_name "CoordinationWorkItemDetail"

    field :attempt, CoordinationAttemptType, null: true
    field :checkpoint, CoordinationCheckpointType, null: true
    field :work_item, CoordinationWorkItemType, null: false
  end
end
