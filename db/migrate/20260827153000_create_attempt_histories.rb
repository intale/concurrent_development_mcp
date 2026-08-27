# frozen_string_literal: true

class CreateAttemptHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :attempt_histories, id: false do |t|
      t.string :attempt_id, null: false, primary_key: true
      t.string :change_set_id, null: false
      t.string :work_item_id, null: false
      t.string :agent_id, null: false
      t.jsonb :base_snapshots, null: false, default: []
      t.string :status, null: false
      t.jsonb :authorization_event, null: false, default: {}
      t.bigint :authorized_global_position, null: false
      t.datetime :authorized_at_domain, null: false
      t.datetime :started_at_domain
      t.string :selected_candidate_id
      t.jsonb :selected_candidate_event
      t.string :abandonment_reason
      t.jsonb :terminal_event
      t.datetime :terminal_at_domain
      t.timestamps
    end

    add_index :attempt_histories,
              [ :work_item_id, :authorized_global_position, :attempt_id ],
              name: "idx_attempt_histories_work_item_cursor",
              unique: true
    add_index :attempt_histories, :change_set_id
    add_index :attempt_histories, :status
  end
end
