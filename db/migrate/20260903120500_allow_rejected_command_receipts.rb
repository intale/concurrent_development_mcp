# frozen_string_literal: true

class AllowRejectedCommandReceipts < ActiveRecord::Migration[8.0]
  def change
    change_column_null :command_receipts, :receipt, true
  end
end
