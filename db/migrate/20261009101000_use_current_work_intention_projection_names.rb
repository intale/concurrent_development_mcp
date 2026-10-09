# frozen_string_literal: true

class UseCurrentWorkIntentionProjectionNames < ActiveRecord::Migration[8.1]
  def up
    execute "DROP VIEW resource_work_intention_browser_rows"

    rename_column :candidates, :lease_set_id, :intention_set_id
    rename_column :candidates, :lease_policy_version, :intention_policy_version
    rename_column :candidates, :lease_references, :intentions

    rename_column :attempt_histories, :write_set_lease_set_id, :work_intention_set_id
    rename_column :attempt_histories, :write_set_repository_id, :work_intention_set_repository_id
    rename_column :attempt_histories, :write_set_policy_version, :work_intention_set_policy_version
    rename_column :attempt_histories, :write_set_resources, :work_intention_set_intentions
    rename_column :attempt_histories, :write_set_reserved_event, :work_intention_set_declared_event
    rename_column :attempt_histories, :write_set_reserved_at_domain, :work_intention_set_declared_at_domain
    rename_column :attempt_histories, :write_set_last_expanded_event, :work_intention_set_last_expanded_event
    rename_column :attempt_histories, :write_set_last_expanded_at_domain, :work_intention_set_last_expanded_at_domain
    rename_column :attempt_histories, :write_set_last_renewed_event, :work_intention_set_last_renewed_event
    rename_column :attempt_histories, :write_set_last_renewed_at_domain, :work_intention_set_last_renewed_at_domain
    rename_column :attempt_histories, :write_set_previous_expires_at_domain,
                  :work_intention_set_previous_expires_at_domain
    rename_column :attempt_histories, :write_set_expires_at_domain, :work_intention_set_expires_at_domain
    rename_column :attempt_histories, :write_set_release_event, :work_intention_set_withdrawal_event
    rename_column :attempt_histories, :write_set_released_at_domain, :work_intention_set_withdrawn_at_domain

    rename_index :attempt_histories, "idx_attempt_histories_current_write_sets",
                 "idx_attempt_histories_current_work_intention_sets"
    rename_index :attempt_histories, "idx_attempt_histories_write_set_identity",
                 "idx_attempt_histories_work_intention_set_identity"

    execute <<~SQL
      CREATE VIEW resource_work_intention_browser_rows AS
      SELECT
        membership.value ->> 'intention_id' AS intention_id,
        membership.value ->> 'resource_id' AS resource_id,
        attempt.work_intention_set_id AS intention_set_id,
        attempt.work_intention_set_repository_id AS repository_id,
        repository.scope AS project_scope,
        repository.display_name AS project_name,
        COALESCE(resource.kind, membership.value ->> 'resource_kind') AS resource_kind,
        COALESCE(resource.normalized_path, membership.value ->> 'resource_path') AS resource_path,
        resource.lifecycle_status AS resource_lifecycle_status,
        membership.value ->> 'base_blob_oid' AS base_blob_oid,
        membership.value ->> 'mode' AS mode,
        membership.value ->> 'purpose' AS purpose,
        membership.value ->> 'context' AS context,
        (membership.value ->> 'fencing_token')::bigint AS fencing_token,
        attempt.work_intention_set_policy_version AS policy_version,
        attempt.change_set_id,
        attempt.work_item_id,
        attempt.attempt_id,
        attempt.agent_id,
        attempt.work_intention_set_declared_event AS declared_event,
        attempt.work_intention_set_declared_at_domain AS declared_at_domain,
        attempt.work_intention_set_last_expanded_event AS last_expanded_event,
        attempt.work_intention_set_last_expanded_at_domain AS last_expanded_at_domain,
        attempt.work_intention_set_last_renewed_event AS last_renewed_event,
        attempt.work_intention_set_last_renewed_at_domain AS last_renewed_at_domain,
        attempt.work_intention_set_previous_expires_at_domain AS previous_expires_at_domain,
        attempt.work_intention_set_expires_at_domain AS expires_at_domain,
        attempt.work_intention_set_withdrawal_event AS withdrawal_event,
        attempt.work_intention_set_withdrawn_at_domain AS withdrawn_at_domain,
        attempt.terminal_event AS attempt_terminal_event,
        attempt.terminal_at_domain AS attempt_terminal_at_domain,
        attempt.updated_at
      FROM attempt_histories AS attempt
      JOIN repositories AS repository
        ON repository.repository_id = attempt.work_intention_set_repository_id
      CROSS JOIN LATERAL jsonb_array_elements(attempt.work_intention_set_intentions) AS membership(value)
      LEFT JOIN resources AS resource
        ON resource.resource_id = membership.value ->> 'resource_id'
       AND resource.repository_id = attempt.work_intention_set_repository_id
      WHERE attempt.work_intention_set_id IS NOT NULL
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
