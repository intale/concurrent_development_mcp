# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_20_184500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "command_receipts", primary_key: "command_id", id: :string, force: :cascade do |t|
    t.string "canonical_input_digest", null: false
    t.bigint "command_stream_revision", null: false
    t.datetime "completed_at_domain", null: false
    t.jsonb "completion", default: {}, null: false
    t.string "context_token", null: false
    t.datetime "created_at", null: false
    t.string "receipt", null: false
    t.string "status", null: false
    t.string "summary", null: false
    t.string "tool_name", null: false
    t.datetime "updated_at", null: false
    t.index ["receipt"], name: "index_command_receipts_on_receipt", unique: true
  end

  create_table "coordinator_context_scopes", id: false, force: :cascade do |t|
    t.string "change_set_id", null: false
    t.datetime "created_at", null: false
    t.string "scope_id", null: false
    t.string "scope_kind", null: false
    t.datetime "updated_at", null: false
    t.index ["change_set_id"], name: "index_coordinator_context_scopes_on_change_set_id"
    t.index ["scope_kind", "scope_id"], name: "idx_coordinator_context_scopes_identity", unique: true
  end

  create_table "coordinator_contexts", primary_key: "change_set_id", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "document", default: {}, null: false
    t.datetime "last_processed_at", null: false
    t.integer "projection_version", null: false
    t.jsonb "source_positions", default: [], null: false
    t.datetime "updated_at", null: false
  end

  create_table "processed_projection_events", id: false, force: :cascade do |t|
    t.string "command_id"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at", null: false
    t.string "projection_name", null: false
    t.integer "projection_version", null: false
    t.string "stream_context", null: false
    t.string "stream_id", null: false
    t.string "stream_name", null: false
    t.bigint "stream_revision", null: false
    t.index ["projection_name", "projection_version", "command_id"], name: "idx_processed_projection_events_command"
    t.index ["projection_name", "projection_version", "stream_context", "stream_name", "stream_id", "stream_revision"], name: "idx_processed_projection_events_identity", unique: true
  end
end
