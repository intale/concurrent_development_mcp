# frozen_string_literal: true

class CreateDevelopmentArtifactObservations < ActiveRecord::Migration[8.1]
  def up
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

    backfill_current_artifacts
  end

  def down
    drop_table :development_artifact_observations
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

  def backfill_current_artifacts
    artifact_model = migration_model(:development_artifacts)
    observation_model = migration_model(:development_artifact_observations)
    canonical_json = Coordinator::Shared::CanonicalJson.new

    artifact_model.find_each do |artifact|
      observation_id = observation_id_for(artifact, canonical_json:)
      evidence = evidence_from_capture(artifact)
      observation_model.create!(
        observation_id:,
        artifact_id: artifact.artifact_id,
        scope: artifact.scope,
        title: artifact.title,
        kind: artifact.kind,
        labels: artifact.labels,
        classification_revision: 1,
        source_kind: artifact.source_kind,
        source_locator: artifact.source_locator,
        source_revision: artifact.source_revision,
        source_observed_at: artifact.source_observed_at,
        source_collector: artifact.source_collector,
        **evidence.transform_keys { "observed_#{_1}" },
        **evidence.transform_keys { "classified_#{_1}" },
        current_global_position: artifact.captured_global_position,
        created_at: artifact.created_at,
        updated_at: artifact.updated_at
      )
    end
  end

  def observation_id_for(artifact, canonical_json:)
    document = {
      schema: "development-artifact-observation-identity/v1",
      artifact_id: artifact.artifact_id,
      scope: artifact.scope,
      source_kind: artifact.source_kind,
      source_locator: artifact.source_locator,
      source_revision: artifact.source_revision,
      source_observed_at: artifact.source_observed_at.utc.iso8601(6),
      source_collector: artifact.source_collector
    }
    digest = canonical_json.sha256(document).delete_prefix("sha256:")
    "artifact-observation:v1:#{digest}"
  end

  def evidence_from_capture(artifact)
    {
      event: artifact.captured_event,
      actor: artifact.captured_actor,
      markers: artifact.captured_markers,
      metadata: artifact.captured_metadata,
      causation_id: artifact.captured_causation_id,
      correlation_id: artifact.captured_correlation_id,
      global_position: artifact.captured_global_position,
      at_domain: artifact.captured_at_domain,
      at_store: artifact.captured_at_store
    }
  end

  def migration_model(table_name)
    Class.new(ActiveRecord::Base) do
      self.table_name = table_name.to_s
      self.inheritance_column = :_type_disabled
    end
  end
end
