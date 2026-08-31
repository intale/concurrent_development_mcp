# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class CoordinationDashboard
    WORK_ITEM_ORDERS = {
      "work_item_id_asc" => { work_item_id: :asc },
      "status_asc" => { presentation_status: :asc, work_item_id: :asc },
      "latest_activity_desc" => Arel.sql(
        "COALESCE(completed_at_domain, attempt_started_at, acquired_at_domain, " \
        "made_ready_at_domain, created_at_domain) DESC, work_item_id ASC"
      )
    }.freeze

    def fetch(query)
      project = Coordinator::Read::Repository.find_by(repository_id: query.repository_id)
      return unless project

      Coordinator::Read::Web::CoordinationDashboardV1.new(
        project: build_project(project),
        change_sets: change_set_page(query),
        work_items: work_item_page(query),
        dependencies: dependency_page(query)
      )
    end

    private

    def build_project(record)
      Coordinator::Read::Web::CoordinationDashboardV1::Project.new(
        repository_id: record.repository_id,
        scope: record.scope,
        display_name: record.display_name
      )
    end

    def change_set_page(query)
      relation = Coordinator::Read::CoordinationDashboardChangeSet
        .where(repository_id: query.repository_id)
        .order(:change_set_id)
      records, has_more = bounded(relation, offset: query.change_set_offset, limit: query.first)

      Coordinator::Read::Web::CoordinationDashboardV1::ChangeSetPage.new(
        items: records.map { build_change_set(_1) },
        next_offset: has_more ? query.change_set_offset + query.first : nil,
        has_more:
      )
    end

    def work_item_page(query)
      relation = Coordinator::Read::CoordinationDashboardWorkItem.where(repository_id: query.repository_id)
      if query.presentation_statuses.any?
        relation = relation.where(presentation_status: query.presentation_statuses)
      end
      relation = relation.order(WORK_ITEM_ORDERS.fetch(query.work_item_sort))
      records, has_more = bounded(relation, offset: query.work_item_offset, limit: query.first)

      Coordinator::Read::Web::CoordinationDashboardV1::WorkItemPage.new(
        items: records.map { build_work_item(_1) },
        next_offset: has_more ? query.work_item_offset + query.first : nil,
        has_more:
      )
    end

    def dependency_page(query)
      relation = Coordinator::Read::CoordinationDashboardDependency.where(
        "producer_repository_id = :repository_id OR consumer_repository_id = :repository_id",
        repository_id: query.repository_id
      )
      relation = relation.where(blocking: query.blocking) unless query.blocking.nil?
      relation = relation.order(:dependency_id)
      records, has_more = bounded(relation, offset: query.dependency_offset, limit: query.first)

      Coordinator::Read::Web::CoordinationDashboardV1::DependencyPage.new(
        items: records.map { build_dependency(_1) },
        next_offset: has_more ? query.dependency_offset + query.first : nil,
        has_more:
      )
    end

    def bounded(relation, offset:, limit:)
      records = relation.offset(offset).limit(limit + 1).to_a
      [ records.first(limit), records.length > limit ]
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
        last_processed_at: timestamp(record.last_processed_at)
      )
    end

    def build_dependency(record)
      Coordinator::Read::Web::CoordinationDashboardV1::Dependency.new(
        dependency_id: record.dependency_id,
        producer_work_item_id: record.producer_work_item_id,
        consumer_work_item_id: record.consumer_work_item_id,
        producer_repository_id: record.producer_repository_id,
        consumer_repository_id: record.consumer_repository_id,
        dependency_kind: record.dependency_kind,
        blocking: record.blocking,
        declared_at: timestamp(record.declared_at_domain),
        satisfied_at: optional_timestamp(record.satisfied_at_domain),
        last_processed_at: timestamp(record.last_processed_at)
      )
    end

    def timestamp(value) = value.utc.iso8601(6)
    def optional_timestamp(value) = value&.utc&.iso8601(6)
  end
end
