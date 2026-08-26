# frozen_string_literal: true

class CreateRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :repositories, id: false do |t|
      t.string :repository_id, null: false, primary_key: true
      t.text :scope, null: false
      t.string :display_name
      t.jsonb :paths, null: false, default: []
      t.jsonb :remotes, null: false, default: []

      t.jsonb :registered_event, null: false
      t.jsonb :registered_actor, null: false
      t.jsonb :registered_markers, null: false, default: []
      t.jsonb :registered_metadata, null: false, default: {}
      t.string :registered_causation_id
      t.string :registered_correlation_id
      t.bigint :registered_global_position, null: false
      t.datetime :registered_at_domain, null: false, precision: 6
      t.datetime :registered_at_store, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :repositories, [ :scope, :repository_id ]
    add_index :repositories, :registered_global_position
  end
end
