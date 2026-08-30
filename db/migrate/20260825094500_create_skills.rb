# frozen_string_literal: true

class CreateSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :skills, id: false do |t|
      t.string :skill_id, null: false, primary_key: true
      t.string :name, null: false
      t.text :scope, null: false
      t.bigint :revision, null: false
      t.timestamps null: false, precision: 6
    end

    add_index :skills, [ :name, :scope ], unique: true

    create_table :skill_revisions do |t|
      t.string :skill_id, null: false
      t.bigint :revision, null: false
      t.text :description, null: false
      t.text :instructions, null: false
      t.string :content_digest, null: false
      t.integer :asset_count, null: false

      t.jsonb :published_event, null: false
      t.jsonb :published_actor, null: false
      t.jsonb :published_markers, null: false, default: []
      t.jsonb :published_metadata, null: false, default: {}
      t.string :published_causation_id
      t.string :published_correlation_id
      t.bigint :published_global_position, null: false
      t.datetime :published_at_domain, null: false, precision: 6
      t.datetime :published_at_store, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :skill_revisions, [ :skill_id, :revision ], unique: true
    add_index :skill_revisions, :published_global_position

    create_table :skill_assets do |t|
      t.string :skill_id, null: false
      t.bigint :revision, null: false
      t.text :path, null: false
      t.string :media_type, null: false
      t.boolean :executable, null: false
      t.string :content_encoding, null: false
      t.text :content_text
      t.text :content_base64
      t.string :content_sha256, null: false
      t.bigint :byte_size, null: false
      t.timestamps null: false, precision: 6
    end

    add_index :skill_assets, [ :skill_id, :revision, :path ], unique: true
    add_foreign_key :skill_revisions, :skills,
                    column: :skill_id,
                    primary_key: :skill_id,
                    on_delete: :cascade
    add_foreign_key :skill_assets, :skills, column: :skill_id, primary_key: :skill_id, on_delete: :cascade
  end
end
