# frozen_string_literal: true

class CreateCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :candidates, id: false do |t|
      t.string :candidate_id, null: false, primary_key: true
      t.string :change_set_id, null: false
      t.string :work_item_id, null: false
      t.string :attempt_id, null: false
      t.string :agent_id, null: false
      t.string :repository_id, null: false
      t.string :target_branch, null: false
      t.string :object_format, null: false
      t.string :base_commit_oid, null: false
      t.string :head_commit_oid, null: false
      t.string :checkpoint_kind, null: false
      t.string :lease_set_id, null: false
      t.string :lease_policy_version, null: false
      t.jsonb :lease_references, null: false, default: []
      t.string :manifest_digest, null: false
      t.string :build_context_digest
      t.string :evidence_status, null: false

      t.jsonb :submitted_event, null: false
      t.jsonb :submitted_actor, null: false
      t.jsonb :submitted_markers, null: false, default: []
      t.jsonb :submitted_metadata, null: false, default: {}
      t.string :submitted_causation_id
      t.string :submitted_correlation_id
      t.bigint :submitted_global_position, null: false
      t.datetime :submitted_at_domain, null: false, precision: 6
      t.datetime :submitted_at_store, null: false, precision: 6

      t.jsonb :manifest
      t.jsonb :manifest_event
      t.jsonb :manifest_actor
      t.jsonb :manifest_markers
      t.jsonb :manifest_metadata
      t.string :manifest_causation_id
      t.string :manifest_correlation_id
      t.bigint :manifest_global_position
      t.datetime :manifest_at_domain, precision: 6
      t.datetime :manifest_at_store, precision: 6

      t.jsonb :build_context
      t.jsonb :build_context_event
      t.jsonb :build_context_actor
      t.jsonb :build_context_markers
      t.jsonb :build_context_metadata
      t.string :build_context_causation_id
      t.string :build_context_correlation_id
      t.bigint :build_context_global_position
      t.datetime :build_context_at_domain, precision: 6
      t.datetime :build_context_at_store, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :candidates,
              [ :attempt_id, :submitted_global_position ],
              name: "idx_candidates_attempt_position"
    add_index :candidates, [ :repository_id, :object_format, :head_commit_oid ], unique: true
    add_index :candidates, :change_set_id
    add_index :candidates, :work_item_id
  end
end
