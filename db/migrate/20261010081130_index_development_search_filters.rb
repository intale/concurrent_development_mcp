# frozen_string_literal: true

class IndexDevelopmentSearchFilters < ActiveRecord::Migration[8.1]
  def change
    # Measured common-body matching scanned/sorted 850 Artifact heads for a
    # 20-row page. Keep an ordered access path as well as selective text GIN.
    add_index :development_artifacts, %i[updated_at artifact_id],
              order: { updated_at: :desc }, name: "idx_search_artifacts_time"
    add_index :development_artifacts, %i[scope updated_at artifact_id],
              order: { updated_at: :desc }, name: "idx_search_artifacts_scope_time"
    add_index :development_artifact_observations, %i[artifact_id observed_sequence],
              order: { observed_sequence: :desc }, name: "idx_search_observations_current"
    add_index :skills, %i[scope updated_at skill_id],
              order: { updated_at: :desc }, name: "idx_search_skills_scope_time"
    add_index :resources, %i[repository_id updated_at resource_id],
              order: { updated_at: :desc }, name: "idx_search_resources_repo_time"
    reversible do |direction|
      direction.up do
        execute <<~SQL
          CREATE INDEX idx_search_choices_repo_time ON agent_choices
            ((context ->> 'repository_id'), updated_at DESC, choice_id)
        SQL
      end
      direction.down { execute "DROP INDEX idx_search_choices_repo_time" }
    end
  end
end
