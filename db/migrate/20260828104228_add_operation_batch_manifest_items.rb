# frozen_string_literal: true

class AddOperationBatchManifestItems < ActiveRecord::Migration[8.1]
  def change
    create_table :operation_batch_items do |t|
      t.string :batch_id, null: false
      t.integer :item_index, null: false
      t.string :target_tool, null: false
      t.string :command_id, null: false
      t.string :canonical_input_digest, null: false
      t.jsonb :arguments, null: false
      t.timestamps null: false, precision: 6
    end

    add_index :operation_batch_items, [ :batch_id, :item_index ], unique: true
    add_index :operation_batch_items, :command_id
    add_foreign_key :operation_batch_items,
                    :operation_batches,
                    column: :batch_id,
                    primary_key: :batch_id,
                    on_delete: :cascade

    change_table :operation_batches, bulk: true do |t|
      t.jsonb :cancellation_actor
      t.jsonb :cancellation_markers, null: false, default: []
      t.jsonb :cancellation_metadata, null: false, default: {}
      t.string :cancellation_causation_id
      t.string :cancellation_correlation_id
      t.bigint :cancellation_global_position
      t.datetime :cancellation_at_domain, precision: 6
      t.datetime :cancellation_at_store, precision: 6
    end
  end
end
