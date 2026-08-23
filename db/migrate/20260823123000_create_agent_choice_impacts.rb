# frozen_string_literal: true

class CreateAgentChoiceImpacts < ActiveRecord::Migration[8.1]
  def change
    change_table :agent_choices, bulk: true do |t|
      t.jsonb :invalidation
      t.jsonb :invalidated_event
      t.jsonb :invalidated_actor
      t.jsonb :invalidated_markers
      t.jsonb :invalidated_metadata
      t.string :invalidated_causation_id
      t.string :invalidated_correlation_id
      t.datetime :invalidated_at_domain, precision: 6
      t.datetime :invalidated_at_store, precision: 6
    end

    create_table :agent_choice_impacts, id: false do |t|
      t.string :assessment_id, null: false, primary_key: true
      t.string :choice_id, null: false
      t.string :attempt_id, null: false
      t.string :outcome, null: false
      t.string :reason, null: false
      t.string :policy_version, null: false
      t.jsonb :accepted_choice, null: false
      t.jsonb :decision_change, null: false
      t.jsonb :assessment, null: false
      t.jsonb :assessment_event, null: false
      t.jsonb :source_actor, null: false
      t.jsonb :assessment_actor, null: false
      t.jsonb :markers, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.string :causation_id
      t.string :correlation_id
      t.bigint :event_global_position, null: false
      t.datetime :assessed_at_domain, null: false, precision: 6
      t.datetime :assessed_at_store, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :agent_choice_impacts,
              [ :attempt_id, :event_global_position ],
              name: "idx_agent_choice_impacts_attempt_position"
    add_index :agent_choice_impacts, :choice_id
    add_index :agent_choice_impacts, :outcome
  end
end
