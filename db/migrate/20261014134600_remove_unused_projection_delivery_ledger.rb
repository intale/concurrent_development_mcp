# frozen_string_literal: true

class RemoveUnusedProjectionDeliveryLedger < ActiveRecord::Migration[8.0]
  def up
    drop_table :processed_projection_events
  end

  def down
    create_table :processed_projection_events, id: false do |table|
      table.string :projection_name, null: false
      table.integer :projection_version, null: false
      table.string :event_id, null: false
      table.string :event_type, null: false
      table.string :stream_context, null: false
      table.string :stream_name, null: false
      table.string :stream_id, null: false
      table.bigint :stream_revision, null: false
      table.string :command_id
      table.datetime :processed_at, null: false
      table.datetime :updated_at, null: false
    end
    add_index :processed_projection_events, %i[projection_name projection_version stream_context stream_name stream_id stream_revision],
      unique: true, name: "idx_processed_projection_events_identity"
    add_index :processed_projection_events, %i[projection_name projection_version command_id],
      name: "idx_processed_projection_events_command"
  end
end
