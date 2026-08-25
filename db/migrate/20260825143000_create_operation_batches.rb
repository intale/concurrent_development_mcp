# frozen_string_literal: true

class CreateOperationBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :operation_batches, id: false do |t|
      t.string :batch_id, null: false, primary_key: true
      t.string :target_tool
      t.integer :total
      t.integer :page_size
      t.string :manifest_digest
      t.bigint :encoded_byte_size
      t.string :status, null: false, default: "running"
      t.integer :succeeded_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.boolean :cancellation_requested, null: false, default: false
      t.string :terminal_kind
      t.jsonb :created_event
      t.jsonb :created_actor
      t.jsonb :created_markers, null: false, default: []
      t.jsonb :created_metadata, null: false, default: {}
      t.string :created_causation_id
      t.string :created_correlation_id
      t.bigint :created_global_position
      t.datetime :created_at_domain, precision: 6
      t.datetime :created_at_store, precision: 6
      t.jsonb :cancellation_event
      t.jsonb :terminal_event
      t.jsonb :terminal_actor
      t.jsonb :terminal_markers, null: false, default: []
      t.jsonb :terminal_metadata, null: false, default: {}
      t.string :terminal_causation_id
      t.string :terminal_correlation_id
      t.bigint :terminal_global_position
      t.datetime :terminal_at_domain, precision: 6
      t.datetime :terminal_at_store, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :operation_batches, :status
    add_index :operation_batches, :created_global_position

    create_table :operation_batch_outcomes do |t|
      t.string :batch_id, null: false
      t.integer :item_index, null: false
      t.string :command_id, null: false
      t.string :canonical_input_digest, null: false
      t.string :status, null: false
      t.jsonb :result, null: false
      t.jsonb :outcome_event, null: false
      t.jsonb :outcome_actor, null: false
      t.jsonb :outcome_markers, null: false, default: []
      t.jsonb :outcome_metadata, null: false, default: {}
      t.string :outcome_causation_id
      t.string :outcome_correlation_id
      t.bigint :outcome_global_position, null: false
      t.datetime :finished_at_domain, null: false, precision: 6
      t.datetime :finished_at_store, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :operation_batch_outcomes, [ :batch_id, :item_index ], unique: true
    add_index :operation_batch_outcomes, :outcome_global_position
    add_foreign_key :operation_batch_outcomes,
                    :operation_batches,
                    column: :batch_id,
                    primary_key: :batch_id,
                    on_delete: :cascade
  end
end
