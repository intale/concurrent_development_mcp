# frozen_string_literal: true

class AddIntegrationAndVerificationToReleaseSets < ActiveRecord::Migration[8.1]
  def change
    change_table :release_sets, bulk: true do |table|
      table.jsonb :integrations, null: false, default: []
      table.jsonb :verifications, null: false, default: []
      table.string :verification_status, null: false, default: "unverified"
    end

    add_index :release_sets, :verification_status
  end
end
