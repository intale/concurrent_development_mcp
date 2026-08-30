# frozen_string_literal: true

class CreateDevelopmentArtifactObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :development_artifact_observations, id: false do |t|
      t.string :observation_id, null: false, primary_key: true
      t.string :artifact_id, null: false
      t.text :scope
      t.text :title
      t.string :kind
      t.jsonb :labels, null: false, default: []
      t.integer :classification_revision, null: false, default: 1
      t.text :classification_reason

      t.string :source_kind
      t.text :source_locator
      t.text :source_revision
      t.datetime :source_observed_at, precision: 6
      t.string :source_collector

      event_evidence(t, :observed)
      event_evidence(t, :classified)
      t.bigint :current_global_position, null: false
      t.bigserial :observed_sequence, null: false
      t.timestamps null: false, precision: 6
    end

    add_index :development_artifact_observations, :artifact_id
    add_index :development_artifact_observations, :scope
    add_index :development_artifact_observations, :kind
    add_index :development_artifact_observations, :source_kind
    add_index :development_artifact_observations, :source_locator, using: :hash
    add_index :development_artifact_observations, :labels, using: :gin
    add_index :development_artifact_observations, :current_global_position
    add_index :development_artifact_observations, :observed_sequence, unique: true
    add_index :development_artifact_observations,
              %i[scope source_kind source_revision observed_sequence],
              name: "idx_artifact_observations_exact_locator"
  end

  private

  def event_evidence(table, prefix)
    table.jsonb "#{prefix}_event"
    table.jsonb "#{prefix}_actor"
    table.jsonb "#{prefix}_markers", null: false, default: []
    table.jsonb "#{prefix}_metadata", null: false, default: {}
    table.string "#{prefix}_causation_id"
    table.string "#{prefix}_correlation_id"
    table.bigint "#{prefix}_global_position"
    table.datetime "#{prefix}_at_domain", precision: 6
    table.datetime "#{prefix}_at_store", precision: 6
  end
end
