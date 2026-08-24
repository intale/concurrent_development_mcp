# frozen_string_literal: true

class AddEvidenceOutcomesToVerificationObligations < ActiveRecord::Migration[8.1]
  def change
    change_table :verification_obligations, bulk: true do |table|
      table.integer :evidence_count, null: false, default: 0
      table.jsonb :passed_evidence_kinds, null: false, default: []
      table.jsonb :missing_evidence_kinds, null: false, default: []
      table.jsonb :terminal_outcome
      table.jsonb :terminal_event
      table.jsonb :terminal_actor
      table.jsonb :terminal_markers
      table.jsonb :terminal_metadata
      table.string :terminal_causation_id
      table.string :terminal_correlation_id
      table.bigint :terminal_event_global_position
      table.integer :terminal_stream_revision
      table.datetime :terminal_at_domain, precision: 6
      table.datetime :terminal_created_at_store, precision: 6
    end

    create_table :verification_obligation_evidence_items, id: false do |table|
      table.string :evidence_id, null: false, primary_key: true
      table.string :obligation_id, null: false
      table.string :evidence_kind, null: false
      table.string :conclusion, null: false
      table.string :assessment_input_digest, null: false
      table.string :result_digest, null: false
      table.jsonb :submission, null: false
      table.string :event_id, null: false
      table.jsonb :event, null: false
      table.jsonb :actor, null: false
      table.jsonb :markers, null: false, default: []
      table.jsonb :metadata, null: false, default: {}
      table.string :causation_id
      table.string :correlation_id
      table.bigint :event_global_position, null: false
      table.integer :stream_revision, null: false
      table.datetime :produced_at_domain, null: false, precision: 6
      table.datetime :submitted_at_domain, null: false, precision: 6
      table.datetime :created_at_store, null: false, precision: 6
      table.timestamps null: false, precision: 6
    end

    add_index :verification_obligation_evidence_items,
              :event_id,
              unique: true,
              name: "idx_verification_evidence_event"
    add_index :verification_obligation_evidence_items,
              %i[obligation_id stream_revision],
              unique: true,
              name: "idx_verification_evidence_obligation_revision"
    add_index :verification_obligation_evidence_items,
              %i[obligation_id assessment_input_digest],
              unique: true,
              name: "idx_verification_evidence_obligation_digest"
    add_index :verification_obligation_evidence_items,
              %i[obligation_id evidence_kind conclusion],
              name: "idx_verification_evidence_progress"
  end
end
