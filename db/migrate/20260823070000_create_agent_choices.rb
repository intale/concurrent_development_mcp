# frozen_string_literal: true

class CreateAgentChoices < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_choices, id: false do |t|
      t.string :choice_id, null: false, primary_key: true
      t.string :choice_type, null: false
      t.string :observation_status, null: false
      t.jsonb :selected, null: false
      t.jsonb :alternatives, null: false, default: []
      t.text :reason_summary, null: false
      t.jsonb :context, null: false
      t.jsonb :decision_context, null: false
      t.string :context_digest, null: false
      t.jsonb :assessment
      t.jsonb :recorded_event, null: false
      t.jsonb :accepted_event
      t.jsonb :recorded_actor, null: false
      t.jsonb :accepted_actor
      t.jsonb :recorded_markers, null: false, default: []
      t.jsonb :accepted_markers
      t.jsonb :recorded_metadata, null: false, default: {}
      t.jsonb :accepted_metadata
      t.string :recorded_causation_id
      t.string :recorded_correlation_id
      t.string :accepted_causation_id
      t.string :accepted_correlation_id
      t.datetime :recorded_at_domain, null: false, precision: 6
      t.datetime :accepted_at_domain, precision: 6
      t.datetime :recorded_at_store, null: false, precision: 6
      t.datetime :accepted_at_store, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :agent_choices, :choice_type
    add_index :agent_choices, :observation_status
  end
end
