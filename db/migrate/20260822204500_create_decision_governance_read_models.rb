# frozen_string_literal: true

class CreateDecisionGovernanceReadModels < ActiveRecord::Migration[8.1]
  def change
    create_table :decision_definitions, id: false do |t|
      t.string :decision_id, null: false, primary_key: true
      t.string :interpretation_id, null: false
      t.string :source_message_id, null: false
      t.string :policy_status, null: false
      t.string :definition_digest, null: false
      t.jsonb :definition, null: false
      t.jsonb :slot
      t.jsonb :partitions, null: false, default: []
      t.jsonb :classifier, null: false
      t.jsonb :scope_provenance, null: false
      t.jsonb :source_event, null: false
      t.jsonb :proposal_event, null: false
      t.jsonb :acceptance_event, null: false
      t.jsonb :recorded_event, null: false
      t.jsonb :activated_event
      t.jsonb :rationale
      t.jsonb :recorded_actor, null: false
      t.jsonb :activated_actor
      t.jsonb :recorded_markers, null: false, default: []
      t.jsonb :activated_markers
      t.jsonb :recorded_metadata, null: false, default: {}
      t.jsonb :activated_metadata
      t.string :recorded_causation_id
      t.string :recorded_correlation_id
      t.string :activated_causation_id
      t.string :activated_correlation_id
      t.datetime :recorded_at_domain, null: false, precision: 6
      t.datetime :activated_at_domain, precision: 6
      t.datetime :recorded_at_store, null: false, precision: 6
      t.datetime :activated_at_store, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :decision_definitions, :interpretation_id, unique: true
    add_index :decision_definitions, :definition_digest
    add_index :decision_definitions, :policy_status

    create_table :decision_slot_heads, id: false do |t|
      t.string :slot_id, null: false, primary_key: true
      t.string :decision_id, null: false
      t.jsonb :slot, null: false
      t.jsonb :head, null: false
      t.jsonb :opened_event, null: false
      t.jsonb :changed_event
      t.jsonb :actor, null: false
      t.jsonb :markers, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.string :causation_id
      t.string :correlation_id
      t.datetime :opened_at_domain, null: false, precision: 6
      t.datetime :changed_at_domain, precision: 6
      t.datetime :event_created_at, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :decision_slot_heads, :decision_id

    create_table :decision_partition_heads, id: false do |t|
      t.string :partition_id, null: false, primary_key: true
      t.string :decision_id, null: false
      t.jsonb :partition, null: false
      t.bigint :partition_revision, null: false
      t.jsonb :decision, null: false
      t.string :change_kind, null: false
      t.jsonb :event, null: false
      t.jsonb :actor, null: false
      t.jsonb :markers, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.string :causation_id
      t.string :correlation_id
      t.datetime :advanced_at_domain, null: false, precision: 6
      t.datetime :event_created_at, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :decision_partition_heads, :decision_id
    add_index :decision_partition_heads, :partition_revision
  end
end
