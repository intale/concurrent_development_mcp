# frozen_string_literal: true

class AddTargetCommandIdsToOperationBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :operation_batch_items, :target_command_id, :string
    add_index :operation_batch_items, :target_command_id
    add_column :operation_batch_outcomes, :target_command_id, :string
    add_index :operation_batch_outcomes, :target_command_id
    change_column_null :operation_batch_outcomes, :command_id, true
    change_column_null :operation_batch_outcomes, :canonical_input_digest, true
  end
end
