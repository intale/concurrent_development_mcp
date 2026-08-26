# frozen_string_literal: true

class AlignDevelopmentArtifactRelationObservations < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      WITH observation_bound AS (
        SELECT GREATEST(
          COALESCE((SELECT MAX(observed_sequence) FROM development_artifact_relations), 0),
          COALESCE((SELECT MAX(observed_sequence) FROM development_artifact_relation_supersessions), 0)
        ) AS maximum
      )
      SELECT setval(
        pg_get_serial_sequence('development_artifact_relations', 'observed_sequence'),
        GREATEST(maximum, 1),
        maximum > 0
      )
      FROM observation_bound
    SQL
  end

  def down
    # Sequence values are monotonic observation identities and are intentionally not rewound.
  end
end
