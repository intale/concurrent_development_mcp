# frozen_string_literal: true

class DecomposeOperationBatchProjections < ActiveRecord::Migration[8.1]
  def change
    add_column :operation_batch_items, :encoded_byte_size, :bigint
    add_column :operation_batch_outcomes, :completion_event, :jsonb
    add_column :operation_batch_outcomes, :completion_link_event, :jsonb
  end
end
