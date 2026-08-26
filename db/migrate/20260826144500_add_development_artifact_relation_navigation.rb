# frozen_string_literal: true

class AddDevelopmentArtifactRelationNavigation < ActiveRecord::Migration[8.1]
  def up
    change_table :development_artifact_relations, bulk: true do |t|
      t.text :fragment
      t.text :normalized_locator
      t.bigserial :observed_sequence, null: false
    end
    add_index :development_artifact_relations, :observed_sequence, unique: true

    create_table :development_artifact_relation_supersessions, id: false do |t|
      t.string :superseded_relation_id, null: false, primary_key: true
      t.string :source_artifact_id, null: false
      t.string :replacement_relation_id, null: false
      t.text :reason, null: false

      t.jsonb :superseded_event, null: false
      t.jsonb :superseded_actor, null: false
      t.jsonb :superseded_markers, null: false, default: []
      t.jsonb :superseded_metadata, null: false, default: {}
      t.string :superseded_causation_id
      t.string :superseded_correlation_id
      t.bigint :superseded_global_position, null: false
      t.datetime :superseded_at_domain, null: false, precision: 6
      t.datetime :superseded_at_store, null: false, precision: 6
      t.bigserial :observed_sequence, null: false
      t.timestamps null: false, precision: 6
    end

    add_index :development_artifact_relation_supersessions, :source_artifact_id
    add_index :development_artifact_relation_supersessions, :replacement_relation_id
    add_index :development_artifact_relation_supersessions, :superseded_global_position
    add_index :development_artifact_relation_supersessions, :observed_sequence, unique: true
  end

  def down
    drop_table :development_artifact_relation_supersessions
    remove_index :development_artifact_relations, :observed_sequence
    remove_columns :development_artifact_relations,
                   :fragment,
                   :normalized_locator,
                   :observed_sequence
  end
end
