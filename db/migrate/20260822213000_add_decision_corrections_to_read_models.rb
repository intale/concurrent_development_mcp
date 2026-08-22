# frozen_string_literal: true

class AddDecisionCorrectionsToReadModels < ActiveRecord::Migration[8.1]
  def change
    change_column_null :decision_slot_heads, :decision_id, true
    change_column_null :decision_slot_heads, :head, true

    change_table :decision_definitions, bulk: true do |table|
      table.string :previous_definition_digest
      table.jsonb :correction_rationale
      table.jsonb :corrected_event
      table.jsonb :corrected_actor
      table.jsonb :corrected_markers, null: false, default: []
      table.jsonb :corrected_metadata, null: false, default: {}
      table.string :corrected_causation_id
      table.string :corrected_correlation_id
      table.datetime :corrected_at_domain, precision: 6
      table.datetime :corrected_at_store, precision: 6
      table.integer :correction_count, null: false, default: 0
    end
  end
end
