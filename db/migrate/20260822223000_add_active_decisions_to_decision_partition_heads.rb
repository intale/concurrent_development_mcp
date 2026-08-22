# frozen_string_literal: true

class AddActiveDecisionsToDecisionPartitionHeads < ActiveRecord::Migration[8.1]
  def change
    add_column :decision_partition_heads, :active_decisions, :jsonb, null: false, default: []
  end
end
