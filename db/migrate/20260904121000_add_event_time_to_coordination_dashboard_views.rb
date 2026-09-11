# frozen_string_literal: true

class AddEventTimeToCoordinationDashboardViews < ActiveRecord::Migration[8.1]
  def up
    create_views(include_updated_at: true)
  end

  def down
    execute "DROP VIEW decision_repository_memberships"
    drop_views
    create_views(include_updated_at: false)
    create_decision_repository_memberships
  end

  private

  def drop_views
    execute "DROP VIEW coordination_dashboard_dependencies"
    execute "DROP VIEW coordination_dashboard_change_sets"
    execute "DROP VIEW coordination_dashboard_work_items"
  end

  def create_views(include_updated_at:)
    work_item_updated_at = if include_updated_at
      ", GREATEST(context.updated_at, COALESCE(attempt.updated_at, context.updated_at)) AS updated_at"
    else
      ""
    end
    change_set_updated_at = include_updated_at ? ", MAX(work_item.updated_at) AS updated_at" : ""
    dependency_updated_at = include_updated_at ? ", context.updated_at AS updated_at" : ""

    execute <<~SQL
      CREATE OR REPLACE VIEW coordination_dashboard_work_items AS
      SELECT
        work_item.value ->> 'work_item_id' AS work_item_id,
        work_item.value ->> 'change_set_id' AS change_set_id,
        work_item.value ->> 'repository_id' AS repository_id,
        work_item.value ->> 'goal' AS goal,
        COALESCE(work_item.value -> 'acceptance_criteria', '[]'::jsonb) AS acceptance_criteria,
        COALESCE((work_item.value ->> 'competitive_mode')::boolean, false) AS competitive_mode,
        work_item.value ->> 'status' AS domain_status,
        CASE
          WHEN work_item.value ->> 'status' = 'completed' THEN 'completed'
          WHEN work_item.value ->> 'status' = 'ready' THEN 'ready'
          WHEN work_item.value ->> 'status' = 'acquired' AND attempt.status = 'started' THEN 'running'
          WHEN work_item.value ->> 'status' = 'acquired' THEN 'assigned'
          ELSE 'pending'
        END AS presentation_status,
        work_item.value ->> 'active_attempt_id' AS active_attempt_id,
        COALESCE(attempt.agent_id, work_item.value ->> 'active_agent_id') AS active_agent_id,
        attempt.status AS attempt_status,
        attempt.authorized_at_domain AS attempt_authorized_at,
        attempt.started_at_domain AS attempt_started_at,
        attempt.terminal_at_domain AS attempt_terminal_at,
        NULLIF(work_item.value ->> 'created_at', '')::timestamptz AS created_at_domain,
        NULLIF(work_item.value ->> 'made_ready_at', '')::timestamptz AS made_ready_at_domain,
        NULLIF(work_item.value ->> 'acquired_at', '')::timestamptz AS acquired_at_domain,
        NULLIF(work_item.value ->> 'completed_at', '')::timestamptz AS completed_at_domain,
        context.document -> 'change_set' ->> 'goal' AS change_set_goal,
        COALESCE(context.document -> 'change_set' -> 'acceptance_criteria', '[]'::jsonb)
          AS change_set_acceptance_criteria,
        context.document -> 'change_set' ->> 'status' AS change_set_status,
        context.last_processed_at
        #{work_item_updated_at}
      FROM coordinator_contexts AS context
      CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(context.document -> 'work_items', '[]'::jsonb)
      ) AS work_item(value)
      LEFT JOIN attempt_histories AS attempt
        ON attempt.attempt_id = work_item.value ->> 'active_attempt_id'
       AND attempt.change_set_id = work_item.value ->> 'change_set_id'
       AND attempt.work_item_id = work_item.value ->> 'work_item_id'
    SQL

    execute <<~SQL
      CREATE OR REPLACE VIEW coordination_dashboard_change_sets AS
      SELECT
        work_item.change_set_id,
        work_item.repository_id,
        work_item.change_set_goal AS goal,
        work_item.change_set_acceptance_criteria AS acceptance_criteria,
        work_item.change_set_status AS domain_status,
        COUNT(*)::integer AS work_item_count,
        COUNT(*) FILTER (WHERE work_item.presentation_status = 'running')::integer AS running_work_item_count,
        COUNT(*) FILTER (WHERE work_item.presentation_status IN ('pending', 'ready', 'assigned'))::integer
          AS open_work_item_count,
        MAX(work_item.last_processed_at) AS last_processed_at
        #{change_set_updated_at}
      FROM coordination_dashboard_work_items AS work_item
      GROUP BY
        work_item.change_set_id,
        work_item.repository_id,
        work_item.change_set_goal,
        work_item.change_set_acceptance_criteria,
        work_item.change_set_status
    SQL

    execute <<~SQL
      CREATE OR REPLACE VIEW coordination_dashboard_dependencies AS
      SELECT
        dependency.value ->> 'dependency_id' AS dependency_id,
        dependency.value ->> 'producer_work_item_id' AS producer_work_item_id,
        dependency.value ->> 'consumer_work_item_id' AS consumer_work_item_id,
        producer.repository_id AS producer_repository_id,
        consumer.repository_id AS consumer_repository_id,
        dependency.value ->> 'dependency_kind' AS dependency_kind,
        dependency.value -> 'required_output' AS required_output,
        NULLIF(dependency.value ->> 'declared_at', '')::timestamptz AS declared_at_domain,
        NULLIF(dependency.value ->> 'satisfied_at', '')::timestamptz AS satisfied_at_domain,
        dependency.value ->> 'satisfied_at' IS NULL AS blocking,
        context.last_processed_at
        #{dependency_updated_at}
      FROM coordinator_contexts AS context
      CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(context.document -> 'dependencies', '[]'::jsonb)
      ) AS dependency(value)
      LEFT JOIN coordination_dashboard_work_items AS producer
        ON producer.change_set_id = context.change_set_id
       AND producer.work_item_id = dependency.value ->> 'producer_work_item_id'
      LEFT JOIN coordination_dashboard_work_items AS consumer
        ON consumer.change_set_id = context.change_set_id
       AND consumer.work_item_id = dependency.value ->> 'consumer_work_item_id'
    SQL
  end

  def create_decision_repository_memberships
    execute <<~SQL
      CREATE VIEW decision_repository_memberships AS
      SELECT
        membership.decision_id,
        membership.repository_id,
        to_jsonb(array_agg(DISTINCT membership.basis ORDER BY membership.basis)) AS membership_bases
      FROM (
        SELECT
          decision.decision_id,
          repository_id.value AS repository_id,
          'explicit_repository'::text AS basis
        FROM decision_definitions AS decision
        CROSS JOIN LATERAL jsonb_array_elements_text(
          COALESCE(decision.definition #> '{document,scope,repository_ids}', '[]'::jsonb)
        ) AS repository_id(value)

        UNION ALL

        SELECT
          decision.decision_id,
          work_item.repository_id,
          'change_set'::text AS basis
        FROM decision_definitions AS decision
        JOIN coordination_dashboard_work_items AS work_item
          ON work_item.change_set_id = decision.definition #>> '{document,scope,change_set_id}'
        UNION ALL

        SELECT
          decision.decision_id,
          work_item.repository_id,
          'work_item'::text AS basis
        FROM decision_definitions AS decision
        JOIN coordination_dashboard_work_items AS work_item
          ON work_item.work_item_id = decision.definition #>> '{document,scope,work_item_id}'
        UNION ALL

        SELECT
          decision.decision_id,
          work_item.repository_id,
          'attempt'::text AS basis
        FROM decision_definitions AS decision
        JOIN attempt_histories AS attempt
          ON attempt.attempt_id = decision.definition #>> '{document,scope,attempt_id}'
        JOIN coordination_dashboard_work_items AS work_item
          ON work_item.change_set_id = attempt.change_set_id
         AND work_item.work_item_id = attempt.work_item_id
        UNION ALL

        SELECT
          decision.decision_id,
          candidate.repository_id,
          'candidate'::text AS basis
        FROM decision_definitions AS decision
        JOIN candidates AS candidate
          ON candidate.candidate_id = decision.definition #>> '{document,scope,candidate_id}'
      ) AS membership
      GROUP BY membership.decision_id, membership.repository_id
    SQL
  end
end
