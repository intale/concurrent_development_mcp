# frozen_string_literal: true

class CreateSkillRevisions < ActiveRecord::Migration[8.1]
  def up
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
    add_foreign_key :skill_revisions, :skills, column: :skill_id, primary_key: :skill_id, on_delete: :cascade

    execute <<~SQL.squish
      INSERT INTO skill_revisions (
        skill_id, revision, description, instructions, content_digest, asset_count,
        published_event, published_actor, published_markers, published_metadata,
        published_causation_id, published_correlation_id, published_global_position,
        published_at_domain, published_at_store, created_at, updated_at
      )
      SELECT
        skill_id, revision, description, instructions, content_digest, asset_count,
        published_event, published_actor, published_markers, published_metadata,
        published_causation_id, published_correlation_id, published_global_position,
        published_at_domain, published_at_store, created_at, updated_at
      FROM skills
    SQL

    remove_index :skill_assets, [ :skill_id, :path ]
    add_index :skill_assets, [ :skill_id, :revision, :path ], unique: true

    remove_index :skills, :published_global_position
    remove_columns :skills,
                   :description,
                   :instructions,
                   :content_digest,
                   :asset_count,
                   :published_event,
                   :published_actor,
                   :published_markers,
                   :published_metadata,
                   :published_causation_id,
                   :published_correlation_id,
                   :published_global_position,
                   :published_at_domain,
                   :published_at_store
  end

  def down
    add_column :skills, :description, :text, null: false, default: ""
    add_column :skills, :instructions, :text, null: false, default: ""
    add_column :skills, :content_digest, :string, null: false, default: ""
    add_column :skills, :asset_count, :integer, null: false, default: 0
    add_column :skills, :published_event, :jsonb, null: false, default: {}
    add_column :skills, :published_actor, :jsonb, null: false, default: {}
    add_column :skills, :published_markers, :jsonb, null: false, default: []
    add_column :skills, :published_metadata, :jsonb, null: false, default: {}
    add_column :skills, :published_causation_id, :string
    add_column :skills, :published_correlation_id, :string
    add_column :skills, :published_global_position, :bigint, null: false, default: 0
    add_column :skills, :published_at_domain, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }
    add_column :skills, :published_at_store, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }

    execute <<~SQL.squish
      UPDATE skills
      SET description = revisions.description,
          instructions = revisions.instructions,
          content_digest = revisions.content_digest,
          asset_count = revisions.asset_count,
          published_event = revisions.published_event,
          published_actor = revisions.published_actor,
          published_markers = revisions.published_markers,
          published_metadata = revisions.published_metadata,
          published_causation_id = revisions.published_causation_id,
          published_correlation_id = revisions.published_correlation_id,
          published_global_position = revisions.published_global_position,
          published_at_domain = revisions.published_at_domain,
          published_at_store = revisions.published_at_store
      FROM skill_revisions AS revisions
      WHERE revisions.skill_id = skills.skill_id
        AND revisions.revision = skills.revision
    SQL

    add_index :skills, :published_global_position
    remove_index :skill_assets, [ :skill_id, :revision, :path ]
    add_index :skill_assets, [ :skill_id, :path ], unique: true
    drop_table :skill_revisions
  end
end
