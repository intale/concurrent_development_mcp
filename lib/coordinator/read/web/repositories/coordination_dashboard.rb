# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class CoordinationDashboard
    STATUS_RANKS = {
      "pending" => 0,
      "ready" => 1,
      "assigned" => 2,
      "running" => 3,
      "completed" => 4
    }.freeze
    STATUS_RANK_SQL = <<~SQL.squish.freeze
      CASE presentation_status
        WHEN 'pending' THEN 0
        WHEN 'ready' THEN 1
        WHEN 'assigned' THEN 2
        WHEN 'running' THEN 3
        WHEN 'completed' THEN 4
      END
    SQL
    LATEST_ACTIVITY_SQL = <<~SQL.squish.freeze
      COALESCE(
        completed_at_domain,
        attempt_terminal_at,
        attempt_started_at,
        acquired_at_domain,
        made_ready_at_domain,
        created_at_domain
      )
    SQL
    CHANGE_SET_SELECT = <<~SQL.squish.freeze
      change_set_id,
      goal,
      acceptance_criteria,
      domain_status,
      SUM(work_item_count)::integer AS work_item_count,
      SUM(running_work_item_count)::integer AS running_work_item_count,
      SUM(open_work_item_count)::integer AS open_work_item_count,
      MAX(last_processed_at) AS last_processed_at,
      MAX(updated_at) AS updated_at
    SQL

    def page(query)
      repository_ids = project_repository_ids(query.scope)
      return if repository_ids.empty?

      case query.kind
      when "change_sets" then change_set_page(query, repository_ids)
      when "work_items" then work_item_page(query, repository_ids)
      when "dependencies" then dependency_page(query, repository_ids)
      end
    end

    def detail(query)
      repository_ids = project_repository_ids(query.scope)
      return if repository_ids.empty?

      case query.kind
      when "change_sets" then change_set_detail(query.id, repository_ids)
      when "work_items" then work_item_detail(query.id, repository_ids)
      when "dependencies" then dependency_detail(query.id, repository_ids)
      end
    end

    private

    def project_repository_ids(scope)
      Coordinator::Read::Repository.where(scope:).pluck(:repository_id)
    end

    def change_set_page(query, repository_ids)
      relation = change_set_relation(repository_ids)
      relation = relation.where(domain_status: query.domain_status) if query.domain_status
      if query.after_id
        comparator = event_time_comparator(query.sort)
        relation = relation.having(
          "MAX(updated_at) #{comparator} :updated_at OR " \
          "(MAX(updated_at) = :updated_at AND change_set_id #{comparator} :id)",
          updated_at: query.after_sort_value,
          id: query.after_id
        )
      end
      records, has_more = bounded(
        relation.order(Arel.sql("MAX(updated_at) #{event_time_direction(query.sort)}, " \
          "change_set_id #{event_time_direction(query.sort)}")),
        query.first
      )

      Coordinator::Read::Web::CoordinationDashboardV1::ChangeSetPage.new(
        items: records.map { build_change_set(_1) },
        next_cursor: page_cursor(records, has_more) { [ _1.change_set_id, timestamp(_1.updated_at) ] },
        has_more:
      )
    end

    def change_set_detail(change_set_id, repository_ids)
      record = change_set_relation(repository_ids).where(change_set_id:).first
      build_change_set(record) if record
    end

    def change_set_relation(repository_ids)
      Coordinator::Read::CoordinationDashboardChangeSet
        .where(repository_id: repository_ids)
        .select(CHANGE_SET_SELECT)
        .group(:change_set_id, :goal, :acceptance_criteria, :domain_status)
    end

    def work_item_page(query, repository_ids)
      relation = work_item_relation(repository_ids)
      relation = relation.where(presentation_status: query.presentation_statuses) if query.presentation_statuses.any?
      relation = relation.where(change_set_id: query.change_set_id) if query.change_set_id
      relation = relation.where(active_agent_id: query.agent_id) if query.agent_id
      relation = apply_work_item_cursor(relation, query)
      records, has_more = bounded(apply_work_item_order(relation, query.work_item_sort), query.first)

      Coordinator::Read::Web::CoordinationDashboardV1::WorkItemPage.new(
        items: records.map { build_work_item(_1) },
        next_cursor: page_cursor(records, has_more) do |record|
          [ record.work_item_id, work_item_sort_value(record, query.work_item_sort) ]
        end,
        has_more:
      )
    end

    def work_item_detail(work_item_id, repository_ids)
      record = work_item_relation(repository_ids).find_by(work_item_id:)
      return unless record

      attempt = latest_attempt(record)
      checkpoint = latest_checkpoint(record)
      Coordinator::Read::Web::CoordinationDashboardV1::WorkItemDetail.new(
        work_item: build_work_item(record),
        attempt: attempt && build_attempt(attempt),
        checkpoint: checkpoint && build_checkpoint(checkpoint)
      )
    end

    def work_item_relation(repository_ids)
      Coordinator::Read::CoordinationDashboardWorkItem
        .where(repository_id: repository_ids)
        .select("coordination_dashboard_work_items.*", "#{LATEST_ACTIVITY_SQL} AS latest_activity_at")
    end

    def apply_work_item_cursor(relation, query)
      return relation unless query.after_id

      case query.work_item_sort
      when "updated_at_desc"
        relation.where(
          "updated_at < :value OR (updated_at = :value AND work_item_id < :id)",
          value: query.after_sort_value,
          id: query.after_id
        )
      when "updated_at_asc"
        relation.where(
          "updated_at > :value OR (updated_at = :value AND work_item_id > :id)",
          value: query.after_sort_value,
          id: query.after_id
        )
      when "status_asc"
        relation.where(
          "#{STATUS_RANK_SQL} > CAST(:value AS integer) OR " \
          "(#{STATUS_RANK_SQL} = CAST(:value AS integer) AND work_item_id > :id)",
          value: query.after_sort_value,
          id: query.after_id
        )
      when "latest_activity_desc"
        relation.where(
          "#{LATEST_ACTIVITY_SQL} < :value OR (#{LATEST_ACTIVITY_SQL} = :value AND work_item_id > :id)",
          value: query.after_sort_value,
          id: query.after_id
        )
      end
    end

    def apply_work_item_order(relation, sort)
      case sort
      when "updated_at_desc" then relation.order(updated_at: :desc, work_item_id: :desc)
      when "updated_at_asc" then relation.order(:updated_at, :work_item_id)
      when "status_asc" then relation.order(Arel.sql("#{STATUS_RANK_SQL} ASC, work_item_id ASC"))
      when "latest_activity_desc" then relation.order(Arel.sql("#{LATEST_ACTIVITY_SQL} DESC, work_item_id ASC"))
      end
    end

    def work_item_sort_value(record, sort)
      case sort
      when "updated_at_desc", "updated_at_asc" then timestamp(record.updated_at)
      when "status_asc" then STATUS_RANKS.fetch(record.presentation_status).to_s
      when "latest_activity_desc" then timestamp(record.latest_activity_at)
      end
    end

    def latest_attempt(record)
      relation = Coordinator::Read::AttemptHistory.where(
        change_set_id: record.change_set_id,
        work_item_id: record.work_item_id
      )
      return relation.find_by(attempt_id: record.active_attempt_id) if record.active_attempt_id

      relation.order(authorized_global_position: :desc, attempt_id: :desc).first
    end

    def latest_checkpoint(record)
      Coordinator::Read::Candidate
        .where(change_set_id: record.change_set_id, work_item_id: record.work_item_id)
        .order(submitted_global_position: :desc, candidate_id: :desc)
        .first
    end

    def dependency_page(query, repository_ids)
      relation = dependency_relation(repository_ids)
      relation = relation.where(blocking: query.blocking) unless query.blocking.nil?
      if query.after_id
        comparator = event_time_comparator(query.sort)
        relation = relation.where(
          "updated_at #{comparator} :updated_at OR " \
          "(updated_at = :updated_at AND dependency_id #{comparator} :id)",
          updated_at: query.after_sort_value,
          id: query.after_id
        )
      end
      direction = query.sort == "oldest_first" ? :asc : :desc
      records, has_more = bounded(relation.order(updated_at: direction, dependency_id: direction), query.first)

      Coordinator::Read::Web::CoordinationDashboardV1::DependencyPage.new(
        items: records.map { build_dependency(_1) },
        next_cursor: page_cursor(records, has_more) { [ _1.dependency_id, timestamp(_1.updated_at) ] },
        has_more:
      )
    end

    def dependency_detail(dependency_id, repository_ids)
      record = dependency_relation(repository_ids).find_by(dependency_id:)
      build_dependency(record) if record
    end

    def dependency_relation(repository_ids)
      Coordinator::Read::CoordinationDashboardDependency.where(
        "producer_repository_id IN (:ids) OR consumer_repository_id IN (:ids)",
        ids: repository_ids
      )
    end

    def bounded(relation, limit)
      records = relation.limit(limit + 1).to_a
      [ records.first(limit), records.length > limit ]
    end

    def event_time_comparator(sort)
      sort == "oldest_first" ? ">" : "<"
    end

    def event_time_direction(sort)
      sort == "oldest_first" ? "ASC" : "DESC"
    end

    def page_cursor(records, has_more)
      return unless has_more

      id, sort_value = yield(records.last)
      Coordinator::Read::Web::CoordinationDashboardV1::Cursor.new(id:, sort_value:)
    end

    def build_change_set(record)
      Coordinator::Read::Web::CoordinationDashboardV1::ChangeSet.new(
        change_set_id: record.change_set_id,
        goal: record.goal,
        acceptance_criteria: record.acceptance_criteria,
        domain_status: record.domain_status,
        work_item_count: record.work_item_count,
        running_work_item_count: record.running_work_item_count,
        open_work_item_count: record.open_work_item_count,
        last_processed_at: timestamp(record.last_processed_at)
      )
    end

    def build_work_item(record)
      Coordinator::Read::Web::CoordinationDashboardV1::WorkItem.new(
        work_item_id: record.work_item_id,
        change_set_id: record.change_set_id,
        repository_id: record.repository_id,
        goal: record.goal,
        acceptance_criteria: record.acceptance_criteria,
        competitive_mode: record.competitive_mode,
        domain_status: record.domain_status,
        presentation_status: record.presentation_status,
        active_attempt_id: record.active_attempt_id,
        active_agent_id: record.active_agent_id,
        attempt_status: record.attempt_status,
        attempt_authorized_at: optional_timestamp(record.attempt_authorized_at),
        attempt_started_at: optional_timestamp(record.attempt_started_at),
        attempt_terminal_at: optional_timestamp(record.attempt_terminal_at),
        created_at: timestamp(record.created_at_domain),
        made_ready_at: optional_timestamp(record.made_ready_at_domain),
        acquired_at: optional_timestamp(record.acquired_at_domain),
        completed_at: optional_timestamp(record.completed_at_domain),
        latest_activity_at: timestamp(record.latest_activity_at),
        last_processed_at: timestamp(record.last_processed_at)
      )
    end

    def build_dependency(record)
      required_output = record.required_output
      Coordinator::Read::Web::CoordinationDashboardV1::Dependency.new(
        dependency_id: record.dependency_id,
        producer_work_item_id: record.producer_work_item_id,
        consumer_work_item_id: record.consumer_work_item_id,
        producer_repository_id: record.producer_repository_id,
        consumer_repository_id: record.consumer_repository_id,
        dependency_kind: record.dependency_kind,
        required_output: required_output && Coordinator::Read::Web::CoordinationDashboardV1::RequiredOutput.new(
          kind: required_output.fetch("kind"),
          key: required_output.fetch("key")
        ),
        blocking: record.blocking,
        declared_at: timestamp(record.declared_at_domain),
        satisfied_at: optional_timestamp(record.satisfied_at_domain),
        last_processed_at: timestamp(record.last_processed_at)
      )
    end

    def build_attempt(record)
      snapshots = record.base_snapshots.map do |snapshot|
        Coordinator::Read::Web::CoordinationDashboardV1::BaseSnapshot.new(
          repository_id: snapshot.fetch("repository_id"),
          object_format: snapshot.fetch("object_format"),
          commit_oid: snapshot.fetch("commit_oid")
        )
      end
      Coordinator::Read::Web::CoordinationDashboardV1::Attempt.new(
        attempt_id: record.attempt_id,
        agent_id: record.agent_id,
        status: record.status,
        base_snapshots: snapshots,
        selected_candidate_id: record.selected_candidate_id,
        abandonment_reason: record.abandonment_reason,
        authorized_at: timestamp(record.authorized_at_domain),
        started_at: optional_timestamp(record.started_at_domain),
        terminal_at: optional_timestamp(record.terminal_at_domain)
      )
    end

    def build_checkpoint(record)
      Coordinator::Read::Web::CoordinationDashboardV1::Checkpoint.new(
        candidate_id: record.candidate_id,
        checkpoint_kind: record.checkpoint_kind,
        target_branch: record.target_branch,
        head_commit_oid: record.head_commit_oid,
        manifest_digest: record.manifest_digest,
        evidence_status: record.evidence_status,
        submitted_at: timestamp(record.submitted_at_domain)
      )
    end

    def timestamp(value) = value.utc.iso8601(6)
    def optional_timestamp(value) = value&.utc&.iso8601(6)
  end
end
