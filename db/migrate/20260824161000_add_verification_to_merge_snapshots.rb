# frozen_string_literal: true

class AddVerificationToMergeSnapshots < ActiveRecord::Migration[8.1]
  def change
    change_table :merge_snapshots, bulk: true do |table|
      table.string :verification_status, null: false, default: "unverified"
      table.string :verification_policy_version,
                   null: false,
                   default: "merge-snapshot-verification/v1"
      table.jsonb :verification_submissions, null: false, default: []
      table.jsonb :verified_decision
    end

    add_index :merge_snapshots, :verification_status
  end
end
