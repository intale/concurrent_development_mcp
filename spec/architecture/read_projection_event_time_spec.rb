# frozen_string_literal: true

RSpec.describe "Read projection event-time schema", :read_model do
  INTERNAL_TABLES = %w[ar_internal_metadata schema_migrations].freeze
  UI_EVENT_TIME_INDEXES = %w[
    idx_agent_choice_impacts_event_time
    idx_agent_choices_event_time
    idx_attempt_histories_event_time
    idx_candidates_event_time
    idx_command_receipts_event_time
    idx_coordinator_contexts_event_time
    idx_decision_definitions_event_time
    idx_decision_interpretations_event_time
    idx_decision_partition_heads_event_time
    idx_decision_slot_heads_event_time
    idx_development_artifact_observations_event_time
    idx_development_artifact_relations_event_time
    idx_merge_authorizations_event_time
    idx_merge_snapshots_event_time
    idx_operation_batches_event_time
    idx_release_sets_event_time
    idx_repositories_event_time
    idx_resources_event_time
    idx_skills_event_time
    idx_user_utterances_event_time
    idx_verification_obligations_event_time
  ].freeze

  it "gives every read table an updated_at timestamp" do
    connection = ActiveRecord::Base.connection
    missing = (connection.tables - INTERNAL_TABLES).reject do |table|
      connection.columns(table).any? { _1.name == "updated_at" }
    end

    expect(missing).to be_empty
  end

  it "keeps a supporting updated_at and stable-ID index for every root UI collection" do
    connection = ActiveRecord::Base.connection
    index_names = connection.tables.flat_map { |table| connection.indexes(table).map(&:name) }

    expect(index_names).to include(*UI_EVENT_TIME_INDEXES)
  end
end
