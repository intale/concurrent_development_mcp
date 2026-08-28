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

ActiveRecord::Schema[8.1].define(version: 2026_08_28_085000) do
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

  create_table "attempt_histories", primary_key: "attempt_id", id: :string, force: :cascade do |t|
    t.string "abandonment_reason"
    t.string "agent_id", null: false
    t.jsonb "authorization_event", default: {}, null: false
    t.datetime "authorized_at_domain", null: false
    t.bigint "authorized_global_position", null: false
    t.jsonb "base_snapshots", default: [], null: false
    t.string "change_set_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "selected_candidate_event"
    t.string "selected_candidate_id"
    t.datetime "started_at_domain"
    t.string "status", null: false
    t.datetime "terminal_at_domain"
    t.jsonb "terminal_event"
    t.datetime "updated_at", null: false
    t.string "work_item_id", null: false
    t.index ["change_set_id"], name: "index_attempt_histories_on_change_set_id"
    t.index ["status"], name: "index_attempt_histories_on_status"
    t.index ["work_item_id", "authorized_global_position", "attempt_id"], name: "idx_attempt_histories_work_item_cursor", unique: true
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

  create_table "development_artifact_observations", primary_key: "observation_id", id: :string, force: :cascade do |t|
    t.string "artifact_id", null: false
    t.text "classification_reason"
    t.integer "classification_revision", default: 1, null: false
    t.jsonb "classified_actor"
    t.datetime "classified_at_domain"
    t.datetime "classified_at_store"
    t.string "classified_causation_id"
    t.string "classified_correlation_id"
    t.jsonb "classified_event"
    t.bigint "classified_global_position"
    t.jsonb "classified_markers", default: [], null: false
    t.jsonb "classified_metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "current_global_position", null: false
    t.string "kind"
    t.jsonb "labels", default: [], null: false
    t.jsonb "observed_actor"
    t.datetime "observed_at_domain"
    t.datetime "observed_at_store"
    t.string "observed_causation_id"
    t.string "observed_correlation_id"
    t.jsonb "observed_event"
    t.bigint "observed_global_position"
    t.jsonb "observed_markers", default: [], null: false
    t.jsonb "observed_metadata", default: {}, null: false
    t.bigserial "observed_sequence", null: false
    t.text "scope"
    t.string "source_collector"
    t.string "source_kind"
    t.text "source_locator"
    t.datetime "source_observed_at"
    t.text "source_revision"
    t.text "title"
    t.datetime "updated_at", null: false
    t.index ["artifact_id"], name: "index_development_artifact_observations_on_artifact_id"
    t.index ["current_global_position"], name: "idx_on_current_global_position_ed0086fb2b"
    t.index ["kind"], name: "index_development_artifact_observations_on_kind"
    t.index ["labels"], name: "index_development_artifact_observations_on_labels", using: :gin
    t.index ["observed_sequence"], name: "index_development_artifact_observations_on_observed_sequence", unique: true
    t.index ["scope", "source_kind", "source_revision", "observed_sequence"], name: "idx_artifact_observations_exact_locator"
    t.index ["scope"], name: "index_development_artifact_observations_on_scope"
    t.index ["source_kind"], name: "index_development_artifact_observations_on_source_kind"
    t.index ["source_locator"], name: "index_development_artifact_observations_on_source_locator", using: :hash
  end

  create_table "development_artifact_relation_supersessions", primary_key: "superseded_relation_id", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigserial "observed_sequence", null: false
    t.text "reason", null: false
    t.string "replacement_relation_id", null: false
    t.string "source_artifact_id", null: false
    t.jsonb "superseded_actor", null: false
    t.datetime "superseded_at_domain", null: false
    t.datetime "superseded_at_store", null: false
    t.string "superseded_causation_id"
    t.string "superseded_correlation_id"
    t.jsonb "superseded_event", null: false
    t.bigint "superseded_global_position", null: false
    t.jsonb "superseded_markers", default: [], null: false
    t.jsonb "superseded_metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["observed_sequence"], name: "idx_on_observed_sequence_9f24f34c1e", unique: true
    t.index ["replacement_relation_id"], name: "idx_on_replacement_relation_id_79c802b934"
    t.index ["source_artifact_id"], name: "idx_on_source_artifact_id_87bf754702"
    t.index ["superseded_global_position"], name: "idx_on_superseded_global_position_379153d0e9"
  end

  create_table "development_artifact_relations", primary_key: "relation_id", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "declared_actor", null: false
    t.datetime "declared_at_domain", null: false
    t.datetime "declared_at_store", null: false
    t.string "declared_causation_id"
    t.string "declared_correlation_id"
    t.jsonb "declared_event", null: false
    t.bigint "declared_global_position", null: false
    t.jsonb "declared_markers", default: [], null: false
    t.jsonb "declared_metadata", default: {}, null: false
    t.text "fragment"
    t.text "normalized_locator"
    t.bigserial "observed_sequence", null: false
    t.text "path"
    t.string "relation", null: false
    t.string "source_artifact_id", null: false
    t.text "target_id", null: false
    t.string "target_kind", null: false
    t.datetime "updated_at", null: false
    t.index ["declared_global_position"], name: "idx_on_declared_global_position_66c5eb75e9"
    t.index ["observed_sequence"], name: "index_development_artifact_relations_on_observed_sequence", unique: true
    t.index ["source_artifact_id"], name: "index_development_artifact_relations_on_source_artifact_id"
    t.index ["target_kind", "target_id"], name: "idx_on_target_kind_target_id_389d0c51da"
  end

  create_table "development_artifacts", primary_key: "artifact_id", id: :string, force: :cascade do |t|
    t.jsonb "captured_actor", null: false
    t.datetime "captured_at_domain", null: false
    t.datetime "captured_at_store", null: false
    t.string "captured_causation_id"
    t.string "captured_correlation_id"
    t.jsonb "captured_event", null: false
    t.bigint "captured_global_position", null: false
    t.jsonb "captured_markers", default: [], null: false
    t.jsonb "captured_metadata", default: {}, null: false
    t.text "content_base64", null: false
    t.bigint "content_byte_size", null: false
    t.string "content_encoding", null: false
    t.string "content_media_type", null: false
    t.string "content_sha256", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "labels", default: [], null: false
    t.bigserial "observed_sequence", null: false
    t.text "scope", null: false
    t.string "source_collector", null: false
    t.string "source_kind", null: false
    t.text "source_locator", null: false
    t.datetime "source_observed_at", null: false
    t.text "source_revision"
    t.text "title", null: false
    t.datetime "updated_at", null: false
    t.index ["captured_global_position"], name: "index_development_artifacts_on_captured_global_position"
    t.index ["kind"], name: "index_development_artifacts_on_kind"
    t.index ["labels"], name: "index_development_artifacts_on_labels", using: :gin
    t.index ["observed_sequence"], name: "index_development_artifacts_on_observed_sequence", unique: true
    t.index ["scope", "source_kind", "source_revision", "observed_sequence"], name: "index_development_artifacts_on_exact_locator_context"
    t.index ["scope"], name: "index_development_artifacts_on_scope"
    t.index ["source_kind"], name: "index_development_artifacts_on_source_kind"
    t.index ["source_locator"], name: "index_development_artifacts_on_source_locator_hash", using: :hash
  end

  create_table "merge_authorizations", primary_key: "authorization_id", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "decided_at_domain", null: false
    t.string "decision_digest", null: false
    t.jsonb "evaluation", null: false
    t.jsonb "expected_impact_policy"
    t.string "input_digest", null: false
    t.string "merge_snapshot_id", null: false
    t.string "outcome", null: false
    t.string "policy_version", null: false
    t.jsonb "snapshot_binding", null: false
    t.jsonb "source_actor", null: false
    t.string "source_causation_id"
    t.string "source_correlation_id"
    t.jsonb "source_event", null: false
    t.bigint "source_global_position", null: false
    t.jsonb "source_markers", default: [], null: false
    t.jsonb "source_metadata", default: {}, null: false
    t.datetime "source_persisted_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merge_snapshot_id", "source_global_position"], name: "idx_merge_authorizations_snapshot_position"
    t.index ["source_global_position"], name: "index_merge_authorizations_on_source_global_position", unique: true
  end

  create_table "merge_snapshots", primary_key: "merge_snapshot_id", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "evidence_status", null: false
    t.string "merge_commit_oid", null: false
    t.string "object_format", null: false
    t.jsonb "observation"
    t.jsonb "ordered_candidates", null: false
    t.string "policy_version", null: false
    t.datetime "produced_at_domain", null: false
    t.jsonb "producer", null: false
    t.jsonb "registered_actor", null: false
    t.datetime "registered_at_domain", null: false
    t.datetime "registered_at_store", null: false
    t.string "registered_causation_id"
    t.string "registered_correlation_id"
    t.jsonb "registered_event", null: false
    t.bigint "registered_global_position", null: false
    t.jsonb "registered_markers", default: [], null: false
    t.jsonb "registered_metadata", default: {}, null: false
    t.string "repository_id", null: false
    t.string "run_id", null: false
    t.string "snapshot_digest", null: false
    t.string "target_base_commit_oid", null: false
    t.string "target_branch", null: false
    t.datetime "updated_at", null: false
    t.string "verification_policy_version", default: "merge-snapshot-verification/v1", null: false
    t.string "verification_status", default: "unverified", null: false
    t.jsonb "verification_submissions", default: [], null: false
    t.jsonb "verified_decision"
    t.index ["registered_global_position"], name: "index_merge_snapshots_on_registered_global_position", unique: true
    t.index ["repository_id", "object_format", "merge_commit_oid"], name: "idx_merge_snapshots_commit_identity", unique: true
    t.index ["verification_status"], name: "index_merge_snapshots_on_verification_status"
  end

  create_table "operation_batch_outcomes", force: :cascade do |t|
    t.string "batch_id", null: false
    t.string "canonical_input_digest", null: false
    t.string "command_id", null: false
    t.datetime "created_at", null: false
    t.datetime "finished_at_domain", null: false
    t.datetime "finished_at_store", null: false
    t.integer "item_index", null: false
    t.jsonb "outcome_actor", null: false
    t.string "outcome_causation_id"
    t.string "outcome_correlation_id"
    t.jsonb "outcome_event", null: false
    t.bigint "outcome_global_position", null: false
    t.jsonb "outcome_markers", default: [], null: false
    t.jsonb "outcome_metadata", default: {}, null: false
    t.jsonb "result", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id", "item_index"], name: "index_operation_batch_outcomes_on_batch_id_and_item_index", unique: true
    t.index ["outcome_global_position"], name: "index_operation_batch_outcomes_on_outcome_global_position"
  end

  create_table "operation_batches", primary_key: "batch_id", id: :string, force: :cascade do |t|
    t.jsonb "cancellation_event"
    t.boolean "cancellation_requested", default: false, null: false
    t.jsonb "created_actor"
    t.datetime "created_at", null: false
    t.datetime "created_at_domain"
    t.datetime "created_at_store"
    t.string "created_causation_id"
    t.string "created_correlation_id"
    t.jsonb "created_event"
    t.bigint "created_global_position"
    t.jsonb "created_markers", default: [], null: false
    t.jsonb "created_metadata", default: {}, null: false
    t.bigint "encoded_byte_size"
    t.string "manifest_digest"
    t.integer "page_size"
    t.integer "rejected_count", default: 0, null: false
    t.string "status", default: "running", null: false
    t.integer "succeeded_count", default: 0, null: false
    t.string "target_tool"
    t.jsonb "terminal_actor"
    t.datetime "terminal_at_domain"
    t.datetime "terminal_at_store"
    t.string "terminal_causation_id"
    t.string "terminal_correlation_id"
    t.jsonb "terminal_event"
    t.bigint "terminal_global_position"
    t.string "terminal_kind"
    t.jsonb "terminal_markers", default: [], null: false
    t.jsonb "terminal_metadata", default: {}, null: false
    t.integer "total"
    t.datetime "updated_at", null: false
    t.index ["created_global_position"], name: "index_operation_batches_on_created_global_position"
    t.index ["status"], name: "index_operation_batches_on_status"
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

  create_table "release_sets", primary_key: "release_set_id", id: :string, force: :cascade do |t|
    t.jsonb "activation"
    t.string "change_set_id", null: false
    t.jsonb "compensation_request"
    t.jsonb "completion"
    t.datetime "created_at", null: false
    t.jsonb "integrations", default: [], null: false
    t.jsonb "ordered_members", null: false
    t.string "preparation_policy_version", null: false
    t.jsonb "prepared_actor", null: false
    t.datetime "prepared_at_domain", null: false
    t.datetime "prepared_at_store", null: false
    t.string "prepared_causation_id"
    t.string "prepared_correlation_id"
    t.jsonb "prepared_event", null: false
    t.bigint "prepared_global_position", null: false
    t.jsonb "prepared_markers", default: [], null: false
    t.jsonb "prepared_metadata", default: {}, null: false
    t.string "release_digest", null: false
    t.string "status", default: "prepared", null: false
    t.datetime "updated_at", null: false
    t.string "verification_status", default: "unverified", null: false
    t.jsonb "verifications", default: [], null: false
    t.index ["change_set_id"], name: "index_release_sets_on_change_set_id"
    t.index ["prepared_global_position"], name: "index_release_sets_on_prepared_global_position", unique: true
    t.index ["status"], name: "index_release_sets_on_status"
    t.index ["verification_status"], name: "index_release_sets_on_verification_status"
  end

  create_table "repositories", primary_key: "repository_id", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.jsonb "paths", default: [], null: false
    t.jsonb "registered_actor", null: false
    t.datetime "registered_at_domain", null: false
    t.datetime "registered_at_store", null: false
    t.string "registered_causation_id"
    t.string "registered_correlation_id"
    t.jsonb "registered_event", null: false
    t.bigint "registered_global_position", null: false
    t.jsonb "registered_markers", default: [], null: false
    t.jsonb "registered_metadata", default: {}, null: false
    t.jsonb "remotes", default: [], null: false
    t.text "scope", null: false
    t.datetime "updated_at", null: false
    t.index ["registered_global_position"], name: "index_repositories_on_registered_global_position"
    t.index ["scope", "repository_id"], name: "index_repositories_on_scope_and_repository_id"
  end

  create_table "skill_assets", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.text "content_base64", null: false
    t.string "content_sha256", null: false
    t.datetime "created_at", null: false
    t.boolean "executable", null: false
    t.string "media_type", null: false
    t.text "path", null: false
    t.bigint "revision", null: false
    t.string "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["skill_id", "revision", "path"], name: "index_skill_assets_on_skill_id_and_revision_and_path", unique: true
  end

  create_table "skill_revisions", force: :cascade do |t|
    t.integer "asset_count", null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.text "instructions", null: false
    t.jsonb "published_actor", null: false
    t.datetime "published_at_domain", null: false
    t.datetime "published_at_store", null: false
    t.string "published_causation_id"
    t.string "published_correlation_id"
    t.jsonb "published_event", null: false
    t.bigint "published_global_position", null: false
    t.jsonb "published_markers", default: [], null: false
    t.jsonb "published_metadata", default: {}, null: false
    t.bigint "revision", null: false
    t.string "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["published_global_position"], name: "index_skill_revisions_on_published_global_position"
    t.index ["skill_id", "revision"], name: "index_skill_revisions_on_skill_id_and_revision", unique: true
  end

  create_table "skills", primary_key: "skill_id", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "revision", null: false
    t.text "scope", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "scope"], name: "index_skills_on_name_and_scope", unique: true
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

  create_table "verification_obligation_evidence_items", primary_key: "evidence_id", id: :string, force: :cascade do |t|
    t.jsonb "actor", null: false
    t.string "assessment_input_digest", null: false
    t.string "causation_id"
    t.string "conclusion", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.datetime "created_at_store", null: false
    t.jsonb "event", null: false
    t.bigint "event_global_position", null: false
    t.string "event_id", null: false
    t.string "evidence_kind", null: false
    t.jsonb "markers", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "obligation_id", null: false
    t.datetime "produced_at_domain", null: false
    t.string "result_digest", null: false
    t.integer "stream_revision", null: false
    t.jsonb "submission", null: false
    t.datetime "submitted_at_domain", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "idx_verification_evidence_event", unique: true
    t.index ["obligation_id", "assessment_input_digest"], name: "idx_verification_evidence_obligation_digest", unique: true
    t.index ["obligation_id", "evidence_kind", "conclusion"], name: "idx_verification_evidence_progress"
    t.index ["obligation_id", "stream_revision"], name: "idx_verification_evidence_obligation_revision", unique: true
  end

  create_table "verification_obligations", primary_key: "obligation_id", id: :string, force: :cascade do |t|
    t.jsonb "actor", null: false
    t.string "causation_id"
    t.string "change_set_id", null: false
    t.jsonb "claim"
    t.jsonb "claim_actor"
    t.string "claim_causation_id"
    t.datetime "claim_claimed_at_domain"
    t.string "claim_correlation_id"
    t.datetime "claim_created_at_store"
    t.jsonb "claim_event"
    t.bigint "claim_event_global_position"
    t.datetime "claim_expires_at_domain"
    t.integer "claim_fencing_token"
    t.string "claim_id"
    t.jsonb "claim_markers"
    t.jsonb "claim_metadata"
    t.integer "claim_stream_revision"
    t.string "claimant_id"
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.datetime "created_at_domain", null: false
    t.datetime "created_at_store", null: false
    t.string "enforcement", null: false
    t.jsonb "event", null: false
    t.bigint "event_global_position", null: false
    t.integer "evidence_count", default: 0, null: false
    t.string "kind", null: false
    t.jsonb "markers", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "missing_evidence_kinds", default: [], null: false
    t.jsonb "obligation", null: false
    t.jsonb "passed_evidence_kinds", default: [], null: false
    t.string "source_candidate_id", null: false
    t.string "source_repository_id", null: false
    t.string "source_work_item_id", null: false
    t.string "status", null: false
    t.string "target_candidate_id", null: false
    t.string "target_repository_id", null: false
    t.string "target_work_item_id", null: false
    t.jsonb "terminal_actor"
    t.datetime "terminal_at_domain"
    t.string "terminal_causation_id"
    t.string "terminal_correlation_id"
    t.datetime "terminal_created_at_store"
    t.jsonb "terminal_event"
    t.bigint "terminal_event_global_position"
    t.jsonb "terminal_markers"
    t.jsonb "terminal_metadata"
    t.jsonb "terminal_outcome"
    t.integer "terminal_stream_revision"
    t.datetime "updated_at", null: false
    t.index ["change_set_id", "status", "event_global_position"], name: "idx_verification_obligations_change_set"
    t.index ["claim_expires_at_domain", "event_global_position"], name: "idx_verification_obligations_claim_expiry"
    t.index ["claimant_id", "event_global_position"], name: "idx_verification_obligations_claimant"
    t.index ["enforcement", "event_global_position"], name: "idx_verification_obligations_enforcement"
    t.index ["event_global_position"], name: "idx_verification_obligations_position"
    t.index ["kind", "event_global_position"], name: "idx_verification_obligations_kind"
    t.index ["source_candidate_id", "event_global_position"], name: "idx_verification_obligations_source_candidate"
    t.index ["source_repository_id", "event_global_position"], name: "idx_verification_obligations_source_repository"
    t.index ["source_work_item_id", "event_global_position"], name: "idx_verification_obligations_source_work_item"
    t.index ["status", "event_global_position"], name: "idx_verification_obligations_status"
    t.index ["target_candidate_id", "event_global_position"], name: "idx_verification_obligations_target_candidate"
    t.index ["target_repository_id", "event_global_position"], name: "idx_verification_obligations_target_repository"
    t.index ["target_work_item_id", "event_global_position"], name: "idx_verification_obligations_target_work_item"
  end

  add_foreign_key "operation_batch_outcomes", "operation_batches", column: "batch_id", primary_key: "batch_id", on_delete: :cascade
  add_foreign_key "skill_assets", "skills", primary_key: "skill_id", on_delete: :cascade
  add_foreign_key "skill_revisions", "skills", primary_key: "skill_id", on_delete: :cascade
end
