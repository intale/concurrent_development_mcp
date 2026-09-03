# frozen_string_literal: true

class AddRequestIdToCommandReceipts < ActiveRecord::Migration[8.0]
  def up
    add_column :command_receipts, :request_id, :string
    execute <<~SQL.squish
      UPDATE command_receipts
         SET request_id = COALESCE(completion ->> 'command_id', command_id)
    SQL
    change_column_null :command_receipts, :request_id, false
    add_index :command_receipts, :request_id
  end

  def down
    remove_index :command_receipts, :request_id
    remove_column :command_receipts, :request_id
  end
end
