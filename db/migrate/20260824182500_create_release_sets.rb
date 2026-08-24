# frozen_string_literal: true

class CreateReleaseSets < ActiveRecord::Migration[8.1]
  def change
    create_table :release_sets, id: false do |table|
      table.string :release_set_id, null: false, primary_key: true
      table.string :change_set_id, null: false
      table.jsonb :ordered_members, null: false
      table.string :release_digest, null: false
      table.string :status, null: false, default: "prepared"
      table.string :preparation_policy_version, null: false
      table.datetime :prepared_at_domain, null: false, precision: 6
      table.jsonb :prepared_event, null: false
      table.jsonb :prepared_actor, null: false
      table.jsonb :prepared_markers, null: false, default: []
      table.jsonb :prepared_metadata, null: false, default: {}
      table.string :prepared_causation_id
      table.string :prepared_correlation_id
      table.bigint :prepared_global_position, null: false
      table.datetime :prepared_at_store, null: false, precision: 6
      table.timestamps null: false, precision: 6
    end

    add_index :release_sets, :change_set_id
    add_index :release_sets, :status
    add_index :release_sets, :prepared_global_position, unique: true
  end
end
