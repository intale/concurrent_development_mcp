# frozen_string_literal: true

class AddActivationAndCompletionToReleaseSets < ActiveRecord::Migration[8.1]
  def change
    change_table :release_sets, bulk: true do |table|
      table.jsonb :activation
      table.jsonb :compensation_request
      table.jsonb :completion
    end
  end
end
