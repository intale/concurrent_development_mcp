# frozen_string_literal: true

class AllowPartialDevelopmentArtifactProjections < ActiveRecord::Migration[8.1]
  def change
    change_column_null :development_artifact_relation_supersessions, :replacement_relation_id, true

    %i[
      scope title kind
      content_encoding content_media_type content_text content_base64 content_sha256 content_byte_size
      source_kind source_locator source_revision source_observed_at source_collector
      captured_event captured_actor captured_global_position captured_at_domain captured_at_store
    ].each do |column|
      change_column_null :development_artifacts, column, true
    end

    change_column_null :development_artifact_observations, :artifact_id, true
    add_column :development_artifacts, :stream_revision, :bigint, null: false, default: 0
    add_column :development_artifact_observations, :content_encoding, :string
    add_column :development_artifact_observations, :content_media_type, :string
    add_column :development_artifact_observations, :content_text, :text
    add_column :development_artifact_observations, :content_base64, :text
    add_column :development_artifact_observations, :content_sha256, :string
    add_column :development_artifact_observations, :content_byte_size, :bigint

    create_table :development_artifact_observation_fact_links, id: false do |t|
      t.string :link_event_id, null: false, primary_key: true
      t.string :observation_id, null: false
      t.string :artifact_id, null: false
      t.string :role, null: false
      t.jsonb :link_event, null: false
      t.jsonb :link_actor, null: false
      t.jsonb :link_markers, null: false, default: []
      t.jsonb :link_metadata, null: false, default: {}
      t.string :link_causation_id
      t.string :link_correlation_id
      t.bigint :link_global_position, null: false
      t.datetime :link_at_domain, null: false, precision: 6
      t.datetime :link_at_store, null: false, precision: 6
      t.jsonb :observed_fact_event, null: false
      t.string :observed_fact_event_id, null: false
      t.jsonb :observed_fact_data, null: false
      t.jsonb :observed_fact_metadata, null: false, default: {}
      t.datetime :observed_fact_created_at, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :development_artifact_observation_fact_links, :observation_id,
              name: "idx_observation_fact_links_observation"
    add_index :development_artifact_observation_fact_links, :artifact_id,
              name: "idx_observation_fact_links_artifact"
    add_index :development_artifact_observation_fact_links,
              [ :observation_id, :role, :observed_fact_event_id ],
              unique: true,
              name: "idx_observation_fact_links_identity"
  end
end
