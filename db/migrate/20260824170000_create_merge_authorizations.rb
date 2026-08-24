# frozen_string_literal: true

class CreateMergeAuthorizations < ActiveRecord::Migration[8.1]
  def change
    create_table :merge_authorizations, id: false do |table|
      table.string :authorization_id, null: false, primary_key: true
      table.string :merge_snapshot_id, null: false
      table.string :outcome, null: false
      table.string :policy_version, null: false
      table.jsonb :snapshot_binding, null: false
      table.jsonb :expected_impact_policy
      table.jsonb :evaluation, null: false
      table.string :input_digest, null: false
      table.string :decision_digest, null: false
      table.datetime :decided_at_domain, null: false, precision: 6
      table.jsonb :source_event, null: false
      table.jsonb :source_actor, null: false
      table.jsonb :source_markers, null: false, default: []
      table.jsonb :source_metadata, null: false, default: {}
      table.string :source_causation_id
      table.string :source_correlation_id
      table.bigint :source_global_position, null: false
      table.datetime :source_persisted_at, null: false, precision: 6
      table.timestamps null: false, precision: 6
    end

    add_index :merge_authorizations,
              %i[merge_snapshot_id source_global_position],
              name: "idx_merge_authorizations_snapshot_position"
    add_index :merge_authorizations, :source_global_position, unique: true
  end
end
