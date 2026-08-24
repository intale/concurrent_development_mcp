# frozen_string_literal: true

class CreateMergeSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :merge_snapshots, id: false do |table|
      table.string :merge_snapshot_id, null: false, primary_key: true
      table.string :repository_id, null: false
      table.string :target_branch, null: false
      table.string :object_format, null: false
      table.string :target_base_commit_oid, null: false
      table.jsonb :ordered_candidates, null: false
      table.string :merge_commit_oid, null: false
      table.jsonb :producer, null: false
      table.string :run_id, null: false
      table.datetime :produced_at_domain, null: false, precision: 6
      table.string :snapshot_digest, null: false
      table.string :policy_version, null: false
      table.string :evidence_status, null: false
      table.datetime :registered_at_domain, null: false, precision: 6
      table.jsonb :registered_event, null: false
      table.jsonb :registered_actor, null: false
      table.jsonb :registered_markers, null: false, default: []
      table.jsonb :registered_metadata, null: false, default: {}
      table.string :registered_causation_id
      table.string :registered_correlation_id
      table.bigint :registered_global_position, null: false
      table.datetime :registered_at_store, null: false, precision: 6
      table.timestamps null: false, precision: 6
    end

    add_index :merge_snapshots,
              %i[repository_id object_format merge_commit_oid],
              unique: true,
              name: "idx_merge_snapshots_commit_identity"
    add_index :merge_snapshots, :registered_global_position, unique: true
  end
end
