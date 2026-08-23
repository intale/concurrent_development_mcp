# frozen_string_literal: true

class AddCandidateImpactReadModels < ActiveRecord::Migration[8.1]
  def change
    change_table :candidates, bulk: true do |t|
      t.jsonb :impact_surface
      t.jsonb :impact_event
      t.jsonb :impact_actor
      t.jsonb :impact_markers
      t.jsonb :impact_metadata
      t.string :impact_causation_id
      t.string :impact_correlation_id
      t.bigint :impact_global_position
      t.datetime :impact_at_domain, precision: 6
      t.datetime :impact_at_store, precision: 6
    end

    create_table :candidate_changed_resources, id: false do |t|
      t.string :candidate_id, null: false
      t.string :change_set_id, null: false
      t.string :repository_id, null: false
      t.string :path, null: false
      t.timestamps null: false, precision: 6
    end
    add_index :candidate_changed_resources,
              [ :candidate_id, :path ],
              unique: true,
              name: "idx_candidate_changed_resources_identity"
    add_index :candidate_changed_resources,
              [ :change_set_id, :repository_id, :path, :candidate_id ],
              name: "idx_candidate_changed_resources_lookup"

    create_table :candidate_observed_inputs, id: false do |t|
      t.string :candidate_id, null: false
      t.string :change_set_id, null: false
      t.string :repository_id, null: false
      t.string :path, null: false
      t.timestamps null: false, precision: 6
    end
    add_index :candidate_observed_inputs,
              [ :candidate_id, :path ],
              unique: true,
              name: "idx_candidate_observed_inputs_identity"
    add_index :candidate_observed_inputs,
              [ :change_set_id, :repository_id, :path, :candidate_id ],
              name: "idx_candidate_observed_inputs_lookup"

    create_table :candidate_impact_keys, id: false do |t|
      t.string :candidate_id, null: false
      t.string :change_set_id, null: false
      t.string :direction, null: false
      t.string :impact_key, null: false
      t.timestamps null: false, precision: 6
    end
    add_index :candidate_impact_keys,
              [ :candidate_id, :direction, :impact_key ],
              unique: true,
              name: "idx_candidate_impact_keys_identity"
    add_index :candidate_impact_keys,
              [ :change_set_id, :impact_key, :direction, :candidate_id ],
              name: "idx_candidate_impact_keys_lookup"
  end
end
