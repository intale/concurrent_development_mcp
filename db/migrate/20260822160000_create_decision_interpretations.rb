# frozen_string_literal: true

class CreateDecisionInterpretations < ActiveRecord::Migration[8.1]
  def change
    create_table :decision_interpretations, id: false do |t|
      t.string :interpretation_id, null: false, primary_key: true
      t.string :message_id, null: false
      t.jsonb :source_event, null: false
      t.jsonb :source_span
      t.jsonb :classifier, null: false
      t.jsonb :proposed_decision, null: false
      t.jsonb :scope_provenance, null: false
      t.jsonb :ambiguities, null: false, default: []
      t.jsonb :assessment, null: false
      t.string :proposal_status, null: false
      t.string :policy_status, null: false
      t.boolean :clarification_required, null: false, default: false
      t.string :clarification_event_id
      t.bigint :clarification_stream_revision
      t.datetime :clarification_required_at_domain, precision: 6
      t.string :actor_kind, null: false
      t.string :actor_id, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :stream_context, null: false
      t.string :stream_name, null: false
      t.string :stream_id, null: false
      t.bigint :stream_revision, null: false
      t.string :causation_id
      t.string :correlation_id
      t.datetime :proposed_at_domain, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :decision_interpretations, [ :message_id, :stream_revision ], unique: true
    add_index :decision_interpretations, :event_id, unique: true
    add_index :decision_interpretations, :proposal_status
    add_index :decision_interpretations, :clarification_event_id, unique: true
  end
end
