# frozen_string_literal: true

class CreateDecisionRepositoryMemberships < ActiveRecord::Migration[8.1]
  def up
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

  def down
    execute "DROP VIEW decision_repository_memberships"
  end
end
