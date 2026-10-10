# frozen_string_literal: true

class IndexDevelopmentSearchText < ActiveRecord::Migration[8.1]
  # Scalar values stay in existing projections. Arrays use the separate raw
  # values table instead of incorrectly indexing escaped JSON serialization.
  INDEXES = {
    skills: %w[name scope],
    skill_revisions: %w[description instructions],
    skill_assets: %w[path content_text],
    resources: %w[normalized_path kind unbinding_reason],
    development_artifacts: %w[title scope kind content_text source_locator source_revision source_collector],
    development_artifact_observations: %w[title scope kind content_text source_locator source_revision source_collector classification_reason],
    user_utterances: %w[text],
    agent_choices: [ "choice_type", "reason_summary", "(selected ->> 'summary')", "(invalidation ->> 'reason')" ],
    decision_definitions: [
      "(definition #>> '{document,topic,topic_id}')",
      "(definition #>> '{document,value,name}')",
      "(definition #>> '{document,value,action}')",
      "(definition #>> '{document,value,target_id}')",
      "(rationale ->> 'summary')", "(correction_rationale ->> 'summary')"
    ]
  }.freeze

  def up
    INDEXES.each_with_index do |(table, expressions), table_index|
      expressions.each_with_index do |expression, column_index|
        execute "CREATE INDEX idx_search_scalar_#{table_index}_#{column_index} ON #{table} USING gin (#{expression} gin_trgm_ops)"
      end
    end
  end

  def down
    INDEXES.values.each_with_index do |expressions, table_index|
      expressions.each_index { execute "DROP INDEX idx_search_scalar_#{table_index}_#{_1}" }
    end
  end
end
