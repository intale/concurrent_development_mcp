# frozen_string_literal: true

class CreateDevelopmentArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :development_artifacts, id: false do |t|
      t.string :artifact_id, null: false, primary_key: true
      t.text :scope, null: false
      t.text :title, null: false
      t.string :kind, null: false
      t.jsonb :labels, null: false, default: []

      t.string :content_encoding, null: false
      t.string :content_media_type, null: false
      t.text :content_base64, null: false
      t.string :content_sha256, null: false
      t.bigint :content_byte_size, null: false

      t.string :source_kind, null: false
      t.text :source_locator, null: false
      t.text :source_revision
      t.datetime :source_observed_at, null: false, precision: 6
      t.string :source_collector, null: false

      t.jsonb :captured_event, null: false
      t.jsonb :captured_actor, null: false
      t.jsonb :captured_markers, null: false, default: []
      t.jsonb :captured_metadata, null: false, default: {}
      t.string :captured_causation_id
      t.string :captured_correlation_id
      t.bigint :captured_global_position, null: false
      t.datetime :captured_at_domain, null: false, precision: 6
      t.datetime :captured_at_store, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :development_artifacts, :scope
    add_index :development_artifacts, :kind
    add_index :development_artifacts, :source_kind
    add_index :development_artifacts, :captured_global_position
    add_index :development_artifacts, :labels, using: :gin

    create_table :development_artifact_relations, id: false do |t|
      t.string :relation_id, null: false, primary_key: true
      t.string :source_artifact_id, null: false
      t.string :relation, null: false
      t.string :target_kind, null: false
      t.text :target_id, null: false
      t.text :path

      t.jsonb :declared_event, null: false
      t.jsonb :declared_actor, null: false
      t.jsonb :declared_markers, null: false, default: []
      t.jsonb :declared_metadata, null: false, default: {}
      t.string :declared_causation_id
      t.string :declared_correlation_id
      t.bigint :declared_global_position, null: false
      t.datetime :declared_at_domain, null: false, precision: 6
      t.datetime :declared_at_store, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :development_artifact_relations, :source_artifact_id
    add_index :development_artifact_relations, [ :target_kind, :target_id ]
    add_index :development_artifact_relations, :declared_global_position
  end
end
