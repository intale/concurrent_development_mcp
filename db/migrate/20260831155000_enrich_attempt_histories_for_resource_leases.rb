# frozen_string_literal: true

class EnrichAttemptHistoriesForResourceLeases < ActiveRecord::Migration[8.1]
  def up
    add_column :attempt_histories, :write_set_lease_set_id, :string
    add_column :attempt_histories, :write_set_repository_id, :string
    add_column :attempt_histories, :write_set_policy_version, :string
    add_column :attempt_histories, :write_set_resources, :jsonb, null: false, default: []
    add_column :attempt_histories, :write_set_reserved_event, :jsonb
    add_column :attempt_histories, :write_set_reserved_at_domain, :datetime, precision: 6
    add_column :attempt_histories, :write_set_last_expanded_event, :jsonb
    add_column :attempt_histories, :write_set_last_expanded_at_domain, :datetime, precision: 6
    add_column :attempt_histories, :write_set_last_renewed_event, :jsonb
    add_column :attempt_histories, :write_set_last_renewed_at_domain, :datetime, precision: 6
    add_column :attempt_histories, :write_set_previous_expires_at_domain, :datetime, precision: 6
    add_column :attempt_histories, :write_set_expires_at_domain, :datetime, precision: 6
    add_column :attempt_histories, :write_set_release_event, :jsonb
    add_column :attempt_histories, :write_set_released_at_domain, :datetime, precision: 6

    add_index :attempt_histories,
              [ :write_set_repository_id, :write_set_expires_at_domain, :attempt_id ],
              name: "idx_attempt_histories_current_write_sets",
              where: <<~SQL.squish
                write_set_lease_set_id IS NOT NULL AND
                write_set_released_at_domain IS NULL AND
                terminal_at_domain IS NULL
              SQL
    add_index :attempt_histories,
              [ :write_set_lease_set_id, :attempt_id ],
              name: "idx_attempt_histories_write_set_identity",
              unique: true,
              where: "write_set_lease_set_id IS NOT NULL"

    execute <<~SQL
      CREATE VIEW resource_lease_browser_rows AS
      SELECT
        membership.value ->> 'lease_id' AS lease_id,
        membership.value ->> 'resource_id' AS resource_id,
        attempt.write_set_lease_set_id AS lease_set_id,
        attempt.write_set_repository_id AS repository_id,
        repository.scope AS project_scope,
        repository.display_name AS project_name,
        COALESCE(resource.kind, membership.value ->> 'resource_kind') AS resource_kind,
        COALESCE(resource.normalized_path, membership.value ->> 'resource_path') AS resource_path,
        resource.lifecycle_status AS resource_lifecycle_status,
        membership.value ->> 'base_blob_oid' AS base_blob_oid,
        (membership.value ->> 'fencing_token')::bigint AS fencing_token,
        attempt.write_set_policy_version AS policy_version,
        attempt.change_set_id,
        attempt.work_item_id,
        attempt.attempt_id,
        attempt.agent_id,
        attempt.write_set_reserved_event AS reserved_event,
        attempt.write_set_reserved_at_domain AS reserved_at_domain,
        attempt.write_set_last_expanded_event AS last_expanded_event,
        attempt.write_set_last_expanded_at_domain AS last_expanded_at_domain,
        attempt.write_set_last_renewed_event AS last_renewed_event,
        attempt.write_set_last_renewed_at_domain AS last_renewed_at_domain,
        attempt.write_set_previous_expires_at_domain AS previous_expires_at_domain,
        attempt.write_set_expires_at_domain AS expires_at_domain,
        attempt.write_set_release_event AS release_event,
        attempt.write_set_released_at_domain AS released_at_domain,
        attempt.terminal_event AS attempt_terminal_event,
        attempt.terminal_at_domain AS attempt_terminal_at_domain,
        attempt.updated_at AS last_projected_at
      FROM attempt_histories AS attempt
      JOIN repositories AS repository
        ON repository.repository_id = attempt.write_set_repository_id
      CROSS JOIN LATERAL jsonb_array_elements(attempt.write_set_resources) AS membership(value)
      LEFT JOIN resources AS resource
        ON resource.resource_id = membership.value ->> 'resource_id'
       AND resource.repository_id = attempt.write_set_repository_id
      WHERE attempt.write_set_lease_set_id IS NOT NULL
    SQL
  end

  def down
    execute "DROP VIEW resource_lease_browser_rows"

    remove_index :attempt_histories, name: "idx_attempt_histories_write_set_identity"
    remove_index :attempt_histories, name: "idx_attempt_histories_current_write_sets"
    remove_columns :attempt_histories,
                   :write_set_lease_set_id,
                   :write_set_repository_id,
                   :write_set_policy_version,
                   :write_set_resources,
                   :write_set_reserved_event,
                   :write_set_reserved_at_domain,
                   :write_set_last_expanded_event,
                   :write_set_last_expanded_at_domain,
                   :write_set_last_renewed_event,
                   :write_set_last_renewed_at_domain,
                   :write_set_previous_expires_at_domain,
                   :write_set_expires_at_domain,
                   :write_set_release_event,
                   :write_set_released_at_domain
  end
end
