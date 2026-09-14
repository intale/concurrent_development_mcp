# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class ProjectResources
    include EventTimePagination

    def resources(query)
      repository_ids = project_repository_ids(query.scope)
      return if repository_ids.empty?

      relation = Coordinator::Read::Resource.where(repository_id: repository_ids)
      relation = relation.where(kind: query.resource_kind) if query.resource_kind
      if query.resource_lifecycle_status
        relation = relation.where(lifecycle_status: query.resource_lifecycle_status)
      end
      if query.path
        pattern = ActiveRecord::Base.sanitize_sql_like(query.path)
        relation = relation.where("normalized_path ILIKE ?", "%#{pattern}%")
      end
      records, has_more = event_time_page(
        relation:,
        id_column: :resource_id,
        after_updated_at: query.after_updated_at,
        after_id: query.after_id,
        limit: query.first,
        sort: query.sort
      )

      Coordinator::Read::Web::ProjectResourcesV1::ResourcePage.new(
        items: records.map { build_resource_record(_1) },
        next_resource_id: has_more ? records.last.resource_id : nil,
        next_updated_at: has_more ? event_time(records.last) : nil,
        has_more:
      )
    end

    def resource(query, view)
      return unless project_repository_ids(query.scope).include?(view.repository_id)

      build_resource_view(view)
    end

    def active_work_intentions(query)
      repository_ids = project_repository_ids(query.scope)
      return if repository_ids.empty?

      relation = work_intention_relation(repository_ids)
        .where(withdrawn_at_domain: nil, attempt_terminal_at_domain: nil)
        .where("expires_at_domain > ?", Time.iso8601(query.as_of))
      relation = apply_work_intention_filters(relation, query)
      records, has_more = event_time_page(
        relation:,
        id_column: :intention_id,
        timestamp_column: :updated_at,
        after_updated_at: query.after_updated_at,
        after_id: query.after_id,
        limit: query.first,
        sort: query.sort
      )

      Coordinator::Read::Web::ProjectResourcesV1::WorkIntentionPage.new(
        items: records.map { build_work_intention(_1, query.as_of) },
        next_intention_id: has_more ? records.last.intention_id : nil,
        next_updated_at: has_more ? records.last.updated_at.utc.iso8601(6) : nil,
        has_more:,
        as_of: query.as_of
      )
    end

    def work_intention(query)
      repository_ids = project_repository_ids(query.scope)
      return if repository_ids.empty?

      record = work_intention_relation(repository_ids).find_by(intention_id: query.id)
      build_work_intention(record, query.as_of) if record
    end

    private

    def project_repository_ids(scope)
      Coordinator::Read::Repository.where(scope:).pluck(:repository_id)
    end

    def work_intention_relation(repository_ids)
      Coordinator::Read::ResourceWorkIntentionBrowserRow.where(repository_id: repository_ids)
    end

    def apply_work_intention_filters(relation, query)
      relation = relation.where(agent_id: query.agent_id) if query.agent_id
      relation = relation.where(change_set_id: query.change_set_id) if query.change_set_id
      relation = relation.where(work_item_id: query.work_item_id) if query.work_item_id
      relation = relation.where(attempt_id: query.attempt_id) if query.attempt_id
      relation = relation.where(mode: query.mode) if query.mode
      relation
    end

    def bounded(relation, limit)
      records = relation.limit(limit + 1).to_a
      [ records.first(limit), records.length > limit ]
    end

    def build_resource_record(record)
      Coordinator::Read::Web::ProjectResourcesV1::Resource.new(
        resource_id: record.resource_id,
        repository_id: record.repository_id,
        kind: record.kind,
        path: record.normalized_path,
        lifecycle_status: record.lifecycle_status,
        unbinding_reason: record.unbinding_reason,
        registered_event_id: event_id(record.registered_event),
        registered_actor_id: record.registered_actor&.fetch("id", nil),
        registered_at: timestamp(record.registered_at_domain),
        latest_transition_event_id: event_id(record.latest_transition_event),
        latest_transition_actor_id: record.latest_transition_actor&.fetch("id", nil),
        last_transition_at: timestamp(record.latest_transition_at_domain)
      )
    end

    def build_resource_view(view)
      Coordinator::Read::Web::ProjectResourcesV1::Resource.new(
        resource_id: view.resource_id,
        repository_id: view.repository_id,
        kind: view.kind,
        path: view.normalized_path,
        lifecycle_status: view.lifecycle_status,
        unbinding_reason: view.unbinding_reason,
        registered_event_id: view.registered&.event&.event_id,
        registered_actor_id: view.registered&.actor&.id,
        registered_at: view.registered&.occurred_at,
        latest_transition_event_id: view.latest_transition&.event&.event_id,
        latest_transition_actor_id: view.latest_transition&.actor&.id,
        last_transition_at: view.latest_transition&.occurred_at
      )
    end

    def build_work_intention(record, as_of)
      Coordinator::Read::Web::ProjectResourcesV1::WorkIntention.new(
        intention_id: record.intention_id,
        intention_set_id: record.intention_set_id,
        resource_id: record.resource_id,
        repository_id: record.repository_id,
        resource_kind: record.resource_kind,
        resource_path: record.resource_path,
        resource_lifecycle_status: record.resource_lifecycle_status,
        status: work_intention_status(record, as_of),
        base_blob_oid: record.base_blob_oid,
        mode: record.mode,
        purpose: record.purpose,
        context: record.context,
        fencing_token: record.fencing_token,
        policy_version: record.policy_version,
        change_set_id: record.change_set_id,
        work_item_id: record.work_item_id,
        attempt_id: record.attempt_id,
        agent_id: record.agent_id,
        declared_event_id: record.declared_event.fetch("event_id"),
        last_expanded_event_id: event_id(record.last_expanded_event),
        last_renewed_event_id: event_id(record.last_renewed_event),
        withdrawal_event_id: event_id(record.withdrawal_event),
        attempt_terminal_event_id: event_id(record.attempt_terminal_event),
        declared_at: timestamp(record.declared_at_domain),
        last_expanded_at: timestamp(record.last_expanded_at_domain),
        last_renewed_at: timestamp(record.last_renewed_at_domain),
        previous_expires_at: timestamp(record.previous_expires_at_domain),
        expires_at: timestamp(record.expires_at_domain),
        withdrawn_at: timestamp(record.withdrawn_at_domain),
        attempt_terminal_at: timestamp(record.attempt_terminal_at_domain),
        updated_at: timestamp(record.updated_at)
      )
    end

    def work_intention_status(record, as_of)
      return "withdrawn" if record.withdrawn_at_domain
      return "attempt_terminal" if record.attempt_terminal_at_domain
      return "expired" if record.expires_at_domain <= Time.iso8601(as_of)

      "active"
    end

    def event_id(event)
      event&.fetch("event_id", nil)
    end

    def timestamp(value)
      value&.utc&.iso8601(6)
    end
  end
end
