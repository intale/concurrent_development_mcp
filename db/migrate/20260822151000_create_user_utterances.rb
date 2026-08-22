# frozen_string_literal: true

class CreateUserUtterances < ActiveRecord::Migration[8.1]
  def change
    create_table :user_utterances, id: false do |t|
      t.string :message_id, null: false, primary_key: true
      t.string :conversation_id, null: false
      t.text :text, null: false
      t.string :source, null: false
      t.jsonb :anchors, null: false, default: {}
      t.string :actor_kind, null: false
      t.string :actor_id, null: false
      t.string :policy_status, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :stream_context, null: false
      t.string :stream_name, null: false
      t.string :stream_id, null: false
      t.bigint :stream_revision, null: false
      t.string :causation_id
      t.string :correlation_id
      t.datetime :recorded_at_domain, null: false, precision: 6
      t.timestamps null: false, precision: 6
    end

    add_index :user_utterances, :conversation_id
    add_index :user_utterances, :event_id, unique: true
  end
end
