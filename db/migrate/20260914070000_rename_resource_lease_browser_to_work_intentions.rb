# frozen_string_literal: true

class RenameResourceLeaseBrowserToWorkIntentions < ActiveRecord::Migration[8.1]
  def up
    execute "DROP VIEW resource_lease_browser_rows"
    add_index :attempt_histories,
              [ :write_set_repository_id, :updated_at, :attempt_id ],
              order: { updated_at: :desc, attempt_id: :desc },
              name: "idx_attempt_histories_work_intention_browser",
              where: "write_set_lease_set_id IS NOT NULL"

    execute <<~SQL
      CREATE VIEW resource_work_intention_browser_rows AS
      SELECT
        COALESCE(membership.value ->> 'intention_id', membership.value ->> 'lease_id') AS intention_id,
        membership.value ->> 'resource_id' AS resource_id,
        attempt.write_set_lease_set_id AS intention_set_id,
        attempt.write_set_repository_id AS repository_id,
        repository.scope AS project_scope,
        repository.display_name AS project_name,
        COALESCE(resource.kind, membership.value ->> 'resource_kind') AS resource_kind,
        COALESCE(resource.normalized_path, membership.value ->> 'resource_path') AS resource_path,
        resource.lifecycle_status AS resource_lifecycle_status,
        membership.value ->> 'base_blob_oid' AS base_blob_oid,
        COALESCE(membership.value ->> 'mode', 'exclusive') AS mode,
        COALESCE(membership.value ->> 'purpose', 'Legacy Resource reservation') AS purpose,
        membership.value ->> 'context' AS context,
        (membership.value ->> 'fencing_token')::bigint AS fencing_token,
        attempt.write_set_policy_version AS policy_version,
        attempt.change_set_id,
        attempt.work_item_id,
        attempt.attempt_id,
        attempt.agent_id,
        attempt.write_set_reserved_event AS declared_event,
        attempt.write_set_reserved_at_domain AS declared_at_domain,
        attempt.write_set_last_expanded_event AS last_expanded_event,
        attempt.write_set_last_expanded_at_domain AS last_expanded_at_domain,
        attempt.write_set_last_renewed_event AS last_renewed_event,
        attempt.write_set_last_renewed_at_domain AS last_renewed_at_domain,
        attempt.write_set_previous_expires_at_domain AS previous_expires_at_domain,
        attempt.write_set_expires_at_domain AS expires_at_domain,
        attempt.write_set_release_event AS withdrawal_event,
        attempt.write_set_released_at_domain AS withdrawn_at_domain,
        attempt.terminal_event AS attempt_terminal_event,
        attempt.terminal_at_domain AS attempt_terminal_at_domain,
        attempt.updated_at
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
    execute "DROP VIEW resource_work_intention_browser_rows"
    remove_index :attempt_histories, name: "idx_attempt_histories_work_intention_browser"

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
end
