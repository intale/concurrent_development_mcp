# frozen_string_literal: true

class AlignDevelopmentSearchObservationOrder < ActiveRecord::Migration[8.1]
  def up
    remove_index :development_artifact_observations, name: "idx_search_observations_current"
    execute <<~SQL
      CREATE INDEX idx_search_observations_current ON development_artifact_observations
        (artifact_id, observed_global_position DESC NULLS LAST, observation_id DESC)
    SQL
  end

  def down
    remove_index :development_artifact_observations, name: "idx_search_observations_current"
    add_index :development_artifact_observations, %i[artifact_id observed_sequence],
              order: { observed_sequence: :desc }, name: "idx_search_observations_current"
  end
end
