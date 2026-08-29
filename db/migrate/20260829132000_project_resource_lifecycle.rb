# frozen_string_literal: true

class ProjectResourceLifecycle < ActiveRecord::Migration[8.1]
  def change
    create_table :resources, primary_key: :resource_id, id: :string do |t|
      t.string :repository_id, null: false
      t.string :kind, null: false
      t.text :normalized_path, null: false
      t.string :lifecycle_status, null: false
      t.string :unbinding_reason

      t.jsonb :registered_event
      t.jsonb :registered_actor
      t.jsonb :registered_markers, default: [], null: false
      t.jsonb :registered_metadata
      t.string :registered_causation_id
      t.string :registered_correlation_id
      t.bigint :registered_global_position
      t.datetime :registered_at_domain
      t.datetime :registered_at_store

      t.jsonb :latest_transition_event
      t.jsonb :latest_transition_actor
      t.jsonb :latest_transition_markers, default: [], null: false
      t.jsonb :latest_transition_metadata
      t.string :latest_transition_causation_id
      t.string :latest_transition_correlation_id
      t.bigint :latest_transition_global_position
      t.datetime :latest_transition_at_domain
      t.datetime :latest_transition_at_store

      t.timestamps

      t.index [ :repository_id, :kind, :normalized_path ], unique: true,
              name: "idx_resources_on_repository_kind_path"
      t.index [ :repository_id, :lifecycle_status, :resource_id ],
              name: "idx_resources_on_repository_status_id"
      t.index [ :repository_id, :resource_id ], name: "idx_resources_on_repository_id"
      t.index :latest_transition_global_position, unique: true
      t.index :registered_global_position, unique: true
    end
  end
end
