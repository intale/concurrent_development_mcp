# frozen_string_literal: true

class AddEventTimeProjectionOrdering < ActiveRecord::Migration[8.1]
  INDEXES = {
    agent_choice_impacts: %i[updated_at assessment_id],
    agent_choices: %i[updated_at choice_id],
    attempt_histories: %i[updated_at attempt_id],
    candidates: %i[updated_at candidate_id],
    command_receipts: %i[updated_at command_id],
    coordinator_contexts: %i[updated_at change_set_id],
    decision_definitions: %i[updated_at decision_id],
    decision_interpretations: %i[updated_at interpretation_id],
    decision_partition_heads: %i[updated_at partition_id],
    decision_slot_heads: %i[updated_at slot_id],
    development_artifact_observations: %i[updated_at observation_id],
    development_artifact_relations: %i[updated_at relation_id],
    merge_authorizations: %i[updated_at authorization_id],
    merge_snapshots: %i[updated_at merge_snapshot_id],
    operation_batches: %i[updated_at batch_id],
    release_sets: %i[updated_at release_set_id],
    repositories: %i[updated_at repository_id],
    resources: %i[updated_at resource_id],
    skills: %i[updated_at skill_id],
    user_utterances: %i[updated_at message_id],
    verification_obligations: %i[updated_at obligation_id]
  }.freeze

  def up
    add_column :processed_projection_events, :updated_at, :datetime, precision: 6
    execute <<~SQL
      UPDATE processed_projection_events
      SET updated_at = processed_at
    SQL
    change_column_null :processed_projection_events, :updated_at, false

    INDEXES.each do |table, columns|
      add_index table, columns, order: { updated_at: :desc, columns.last => :desc },
                name: "idx_#{table}_event_time"
    end
  end

  def down
    INDEXES.each_key do |table|
      remove_index table, name: "idx_#{table}_event_time"
    end
    remove_column :processed_projection_events, :updated_at
  end
end
