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

ActiveRecord::Schema[8.1].define(version: 2026_08_23_162000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_choice_impacts", primary_key: "assessment_id", id: :string, force: :cascade do |t|
    t.jsonb "accepted_choice", null: false
    t.datetime "assessed_at_domain", null: false
    t.datetime "assessed_at_store", null: false
    t.jsonb "assessment", null: false
    t.jsonb "assessment_actor", null: false
    t.jsonb "assessment_event", null: false
    t.string "attempt_id", null: false
    t.string "causation_id"
    t.string "choice_id", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.jsonb "decision_change", null: false
    t.bigint "event_global_position", null: false
    t.jsonb "markers", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "outcome", null: false
    t.string "policy_version", null: false
    t.string "reason", null: false
    t.jsonb "source_actor", null: false
    t.datetime "updated_at", null: false
    t.index ["attempt_id", "event_global_position"], name: "idx_agent_choice_impacts_attempt_position"
    t.index ["choice_id"], name: "index_agent_choice_impacts_on_choice_id"
    t.index ["outcome"], name: "index_agent_choice_impacts_on_outcome"
  end

  create_table "agent_choices", primary_key: "choice_id", id: :string, force: :cascade do |t|
    t.jsonb "accepted_actor"
    t.datetime "accepted_at_domain"
    t.datetime "accepted_at_store"
    t.string "accepted_causation_id"
    t.string "accepted_correlation_id"
    t.jsonb "accepted_event"
    t.jsonb "accepted_markers"
    t.jsonb "accepted_metadata"
    t.jsonb "alternatives", default: [], null: false
    t.jsonb "assessment"
    t.string "choice_type", null: false
    t.jsonb "context", null: false
    t.string "context_digest", null: false
    t.datetime "created_at", null: false
    t.jsonb "decision_context", null: false
    t.jsonb "invalidated_actor"
    t.datetime "invalidated_at_domain"
    t.datetime "invalidated_at_store"
    t.string "invalidated_causation_id"
    t.string "invalidated_correlation_id"
    t.jsonb "invalidated_event"
    t.jsonb "invalidated_markers"
    t.jsonb "invalidated_metadata"
    t.jsonb "invalidation"
    t.string "observation_status", null: false
    t.text "reason_summary", null: false
    t.jsonb "recorded_actor", null: false
    t.datetime "recorded_at_domain", null: false
    t.datetime "recorded_at_store", null: false
    t.string "recorded_causation_id"
    t.string "recorded_correlation_id"
    t.jsonb "recorded_event", null: false
    t.jsonb "recorded_markers", default: [], null: false
    t.jsonb "recorded_metadata", default: {}, null: false
    t.jsonb "selected", null: false
    t.datetime "updated_at", null: false
    t.index ["choice_type"], name: "index_agent_choices_on_choice_type"
    t.index ["observation_status"], name: "index_agent_choices_on_observation_status"
  end

  create_table "candidate_changed_resources", id: false, force: :cascade do |t|
    t.string "candidate_id", null: false
    t.string "change_set_id", null: false
    t.datetime "created_at", null: false
    t.string "path", null: false
    t.string "repository_id", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "path"], name: "idx_candidate_changed_resources_identity", unique: true
    t.index ["change_set_id", "repository_id", "path", "candidate_id"], name: "idx_candidate_changed_resources_lookup"
  end

  create_table "candidate_impact_keys", id: false, force: :cascade do |t|
    t.string "candidate_id", null: false
    t.string "change_set_id", null: false
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.string "impact_key", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "direction", "impact_key"], name: "idx_candidate_impact_keys_identity", unique: true
    t.index ["change_set_id", "impact_key", "direction", "candidate_id"], name: "idx_candidate_impact_keys_lookup"
  end

  create_table "candidate_observed_inputs", id: false, force: :cascade do |t|
    t.string "candidate_id", null: false
    t.string "change_set_id", null: false
    t.datetime "created_at", null: false
    t.string "path", null: false
    t.string "repository_id", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "path"], name: "idx_candidate_observed_inputs_identity", unique: true
    t.index ["change_set_id", "repository_id", "path", "candidate_id"], name: "idx_candidate_observed_inputs_lookup"
  end

  create_table "candidates", primary_key: "candidate_id", id: :string, force: :cascade do |t|
    t.string "agent_id", null: false
    t.string "attempt_id", null: false
    t.string "base_commit_oid", null: false
    t.jsonb "build_context"
    t.jsonb "build_context_actor"
    t.datetime "build_context_at_domain"
    t.datetime "build_context_at_store"
    t.string "build_context_causation_id"
    t.string "build_context_correlation_id"
    t.string "build_context_digest"
    t.jsonb "build_context_event"
    t.bigint "build_context_global_position"
    t.jsonb "build_context_markers"
    t.jsonb "build_context_metadata"
    t.string "change_set_id", null: false
    t.string "checkpoint_kind", null: false
    t.datetime "created_at", null: false
    t.string "evidence_status", null: false
    t.string "head_commit_oid", null: false
    t.jsonb "impact_actor"
    t.datetime "impact_at_domain"
    t.datetime "impact_at_store"
    t.string "impact_causation_id"
    t.string "impact_correlation_id"
    t.jsonb "impact_event"
    t.bigint "impact_global_position"
    t.jsonb "impact_markers"
    t.jsonb "impact_metadata"
    t.jsonb "impact_surface"
    t.string "lease_policy_version", null: false
    t.jsonb "lease_references", default: [], null: false
    t.string "lease_set_id", null: false
    t.jsonb "manifest"
    t.jsonb "manifest_actor"
    t.datetime "manifest_at_domain"
    t.datetime "manifest_at_store"
    t.string "manifest_causation_id"
    t.string "manifest_correlation_id"
    t.string "manifest_digest", null: false
    t.jsonb "manifest_event"
    t.bigint "manifest_global_position"
    t.jsonb "manifest_markers"
    t.jsonb "manifest_metadata"
    t.string "object_format", null: false
    t.string "repository_id", null: false
    t.jsonb "submitted_actor", null: false
    t.datetime "submitted_at_domain", null: false
    t.datetime "submitted_at_store", null: false
    t.string "submitted_causation_id"
    t.string "submitted_correlation_id"
    t.jsonb "submitted_event", null: false
    t.bigint "submitted_global_position", null: false
    t.jsonb "submitted_markers", default: [], null: false
    t.jsonb "submitted_metadata", default: {}, null: false
    t.string "target_branch", null: false
    t.datetime "updated_at", null: false
    t.string "work_item_id", null: false
    t.index ["attempt_id", "submitted_global_position"], name: "idx_candidates_attempt_position"
    t.index ["change_set_id"], name: "index_candidates_on_change_set_id"
    t.index ["repository_id", "object_format", "head_commit_oid"], name: "idx_on_repository_id_object_format_head_commit_oid_9c83b0d102", unique: true
    t.index ["work_item_id"], name: "index_candidates_on_work_item_id"
  end

  create_table "command_receipts", primary_key: "command_id", id: :string, force: :cascade do |t|
    t.string "canonical_input_digest", null: false
    t.bigint "command_stream_revision", null: false
    t.datetime "completed_at_domain", null: false
    t.jsonb "completion", default: {}, null: false
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

  create_table "decision_definitions", primary_key: "decision_id", id: :string, force: :cascade do |t|
    t.jsonb "acceptance_event", null: false
    t.jsonb "activated_actor"
    t.datetime "activated_at_domain"
    t.datetime "activated_at_store"
    t.string "activated_causation_id"
    t.string "activated_correlation_id"
    t.jsonb "activated_event"
    t.jsonb "activated_markers"
    t.jsonb "activated_metadata"
    t.jsonb "classifier", null: false
    t.jsonb "corrected_actor"
    t.datetime "corrected_at_domain"
    t.datetime "corrected_at_store"
    t.string "corrected_causation_id"
    t.string "corrected_correlation_id"
    t.jsonb "corrected_event"
    t.jsonb "corrected_markers", default: [], null: false
    t.jsonb "corrected_metadata", default: {}, null: false
    t.integer "correction_count", default: 0, null: false
    t.jsonb "correction_rationale"
    t.datetime "created_at", null: false
    t.jsonb "definition", null: false
    t.string "definition_digest", null: false
    t.string "interpretation_id", null: false
    t.jsonb "partitions", default: [], null: false
    t.string "policy_status", null: false
    t.string "previous_definition_digest"
    t.jsonb "proposal_event", null: false
    t.jsonb "rationale"
    t.jsonb "recorded_actor", null: false
    t.datetime "recorded_at_domain", null: false
    t.datetime "recorded_at_store", null: false
    t.string "recorded_causation_id"
    t.string "recorded_correlation_id"
    t.jsonb "recorded_event", null: false
    t.jsonb "recorded_markers", default: [], null: false
    t.jsonb "recorded_metadata", default: {}, null: false
    t.jsonb "scope_provenance", null: false
    t.jsonb "slot"
    t.jsonb "source_event", null: false
    t.string "source_message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["definition_digest"], name: "index_decision_definitions_on_definition_digest"
    t.index ["interpretation_id"], name: "index_decision_definitions_on_interpretation_id", unique: true
    t.index ["policy_status"], name: "index_decision_definitions_on_policy_status"
  end

  create_table "decision_interpretations", primary_key: "interpretation_id", id: :string, force: :cascade do |t|
    t.string "actor_id", null: false
    t.string "actor_kind", null: false
    t.jsonb "adjudication"
    t.jsonb "ambiguities", default: [], null: false
    t.jsonb "assessment", null: false
    t.string "causation_id"
    t.string "clarification_event_id"
    t.boolean "clarification_required", default: false, null: false
    t.datetime "clarification_required_at_domain"
    t.bigint "clarification_stream_revision"
    t.jsonb "classifier", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "lifecycle_status", default: "proposed", null: false
    t.string "message_id", null: false
    t.string "policy_status", null: false
    t.string "proposal_status", null: false
    t.datetime "proposed_at_domain", null: false
    t.jsonb "proposed_decision", null: false
    t.jsonb "scope_provenance", null: false
    t.jsonb "source_event", null: false
    t.jsonb "source_span"
    t.string "stream_context", null: false
    t.string "stream_id", null: false
    t.string "stream_name", null: false
    t.bigint "stream_revision", null: false
    t.datetime "updated_at", null: false
    t.index ["clarification_event_id"], name: "index_decision_interpretations_on_clarification_event_id", unique: true
    t.index ["event_id"], name: "index_decision_interpretations_on_event_id", unique: true
    t.index ["lifecycle_status"], name: "index_decision_interpretations_on_lifecycle_status"
    t.index ["message_id", "stream_revision"], name: "idx_on_message_id_stream_revision_4258fdb4a5", unique: true
    t.index ["proposal_status"], name: "index_decision_interpretations_on_proposal_status"
  end

  create_table "decision_partition_heads", primary_key: "partition_id", id: :string, force: :cascade do |t|
    t.jsonb "active_decisions", default: [], null: false
    t.jsonb "actor", null: false
    t.datetime "advanced_at_domain", null: false
    t.string "causation_id"
    t.string "change_kind", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.jsonb "decision", null: false
    t.string "decision_id", null: false
    t.jsonb "event", null: false
    t.datetime "event_created_at", null: false
    t.jsonb "markers", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "partition", null: false
    t.bigint "partition_revision", null: false
    t.datetime "updated_at", null: false
    t.index ["decision_id"], name: "index_decision_partition_heads_on_decision_id"
    t.index ["partition_revision"], name: "index_decision_partition_heads_on_partition_revision"
  end

  create_table "decision_slot_heads", primary_key: "slot_id", id: :string, force: :cascade do |t|
    t.jsonb "actor", null: false
    t.string "causation_id"
    t.datetime "changed_at_domain"
    t.jsonb "changed_event"
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "decision_id"
    t.datetime "event_created_at", null: false
    t.jsonb "head"
    t.jsonb "markers", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "opened_at_domain", null: false
    t.jsonb "opened_event", null: false
    t.jsonb "slot", null: false
    t.datetime "updated_at", null: false
    t.index ["decision_id"], name: "index_decision_slot_heads_on_decision_id"
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

  create_table "user_utterances", primary_key: "message_id", id: :string, force: :cascade do |t|
    t.string "actor_id", null: false
    t.string "actor_kind", null: false
    t.jsonb "anchors", default: {}, null: false
    t.string "causation_id"
    t.string "conversation_id", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "policy_status", null: false
    t.datetime "recorded_at_domain", null: false
    t.string "source", null: false
    t.string "stream_context", null: false
    t.string "stream_id", null: false
    t.string "stream_name", null: false
    t.bigint "stream_revision", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_user_utterances_on_conversation_id"
    t.index ["event_id"], name: "index_user_utterances_on_event_id", unique: true
  end
end
