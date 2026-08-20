# frozen_string_literal: true

class CreateCoordinatorReadModels < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_projection_events, id: false do |t|
      t.string :projection_name, null: false
      t.integer :projection_version, null: false
      t.string :stream_context, null: false
      t.string :stream_name, null: false
      t.string :stream_id, null: false
      t.bigint :stream_revision, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :command_id
      t.datetime :processed_at, null: false, precision: 6
    end

    add_index :processed_projection_events,
              %i[
                projection_name
                projection_version
                stream_context
                stream_name
                stream_id
                stream_revision
              ],
              unique: true,
              name: "idx_processed_projection_events_identity"
    add_index :processed_projection_events,
              %i[projection_name projection_version command_id],
              name: "idx_processed_projection_events_command"

    create_table :command_receipts, id: false do |t|
      t.string :command_id, null: false, primary_key: true
      t.bigint :command_stream_revision, null: false
      t.string :tool_name, null: false
      t.string :canonical_input_digest, null: false
      t.string :status, null: false
      t.string :summary, null: false
      t.string :receipt, null: false
      t.string :context_token, null: false
      t.jsonb :completion, null: false, default: {}
      t.datetime :completed_at_domain, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :command_receipts, :receipt, unique: true

    create_table :coordinator_contexts, id: false do |t|
      t.string :change_set_id, null: false, primary_key: true
      t.integer :projection_version, null: false
      t.jsonb :document, null: false, default: {}
      t.jsonb :source_positions, null: false, default: []
      t.datetime :last_processed_at, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    create_table :coordinator_context_scopes, id: false do |t|
      t.string :scope_kind, null: false
      t.string :scope_id, null: false
      t.string :change_set_id, null: false
      t.timestamps null: false, precision: 6
    end

    add_index :coordinator_context_scopes,
              %i[scope_kind scope_id],
              unique: true,
              name: "idx_coordinator_context_scopes_identity"
    add_index :coordinator_context_scopes, :change_set_id
  end
end
