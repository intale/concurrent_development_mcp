# frozen_string_literal: true

class AddAdjudicationToDecisionInterpretations < ActiveRecord::Migration[8.1]
  def change
    change_table :decision_interpretations, bulk: true do |t|
      t.string :lifecycle_status, null: false, default: "proposed"
      t.jsonb :adjudication
    end

    add_index :decision_interpretations, :lifecycle_status
  end
end
