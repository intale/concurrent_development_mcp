# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class ProjectResources
    def fetch(query)
      project = Coordinator::Read::Repository.find_by(repository_id: query.repository_id)
      return unless project

      Coordinator::Read::Web::ProjectResourcesV1.new(
        project: build_project(project),
        resources: resource_page(query),
        active_leases: active_lease_page(query),
        lease_as_of: query.lease_as_of
      )
    end

    private

    def build_project(record)
      Coordinator::Read::Web::ProjectResourcesV1::Project.new(
        repository_id: record.repository_id,
        scope: record.scope,
        display_name: record.display_name
      )
    end

    def resource_page(query)
      relation = Coordinator::Read::Resource.where(repository_id: query.repository_id)
      relation = relation.where(kind: query.resource_kind) if query.resource_kind
      if query.resource_lifecycle_status
        relation = relation.where(lifecycle_status: query.resource_lifecycle_status)
      end
      relation = relation.where("resource_id > ?", query.resource_after_id) if query.resource_after_id
      records, has_more = bounded(relation.order(:resource_id), query.first)

      Coordinator::Read::Web::ProjectResourcesV1::ResourcePage.new(
        items: records.map { build_resource(_1) },
        next_resource_id: has_more ? records.last.resource_id : nil,
        has_more:
      )
    end

    def active_lease_page(query)
      relation = Coordinator::Read::ResourceLeaseBrowserRow.where(
        repository_id: query.repository_id,
        released_at_domain: nil,
        attempt_terminal_at_domain: nil
      ).where("expires_at_domain > ?", Time.iso8601(query.lease_as_of))
      relation = relation.where("lease_id > ?", query.lease_after_id) if query.lease_after_id
      records, has_more = bounded(relation.order(:lease_id), query.first)

      Coordinator::Read::Web::ProjectResourcesV1::ActiveLeasePage.new(
        items: records.map { build_active_lease(_1) },
        next_lease_id: has_more ? records.last.lease_id : nil,
        has_more:
      )
    end

    def bounded(relation, limit)
      records = relation.limit(limit + 1).to_a
      [ records.first(limit), records.length > limit ]
    end

    def build_resource(record)
      Coordinator::Read::Web::ProjectResourcesV1::Resource.new(
        resource_id: record.resource_id,
        repository_id: record.repository_id,
        kind: record.kind,
        path: record.normalized_path,
        lifecycle_status: record.lifecycle_status,
        unbinding_reason: record.unbinding_reason,
        registered_at: timestamp(record.registered_at_domain),
        last_transition_at: timestamp(record.latest_transition_at_domain)
      )
    end

    def build_active_lease(record)
      Coordinator::Read::Web::ProjectResourcesV1::ActiveLease.new(
        lease_id: record.lease_id,
        lease_set_id: record.lease_set_id,
        resource_id: record.resource_id,
        repository_id: record.repository_id,
        resource_kind: record.resource_kind,
        resource_path: record.resource_path,
        resource_lifecycle_status: record.resource_lifecycle_status,
        base_blob_oid: record.base_blob_oid,
        fencing_token: record.fencing_token,
        policy_version: record.policy_version,
        change_set_id: record.change_set_id,
        work_item_id: record.work_item_id,
        attempt_id: record.attempt_id,
        agent_id: record.agent_id,
        reserved_event_id: record.reserved_event.fetch("event_id"),
        last_expanded_event_id: event_id(record.last_expanded_event),
        last_renewed_event_id: event_id(record.last_renewed_event),
        reserved_at: record.reserved_at_domain.utc.iso8601(6),
        last_expanded_at: timestamp(record.last_expanded_at_domain),
        last_renewed_at: timestamp(record.last_renewed_at_domain),
        previous_expires_at: timestamp(record.previous_expires_at_domain),
        expires_at: record.expires_at_domain.utc.iso8601(6),
        last_projected_at: record.last_projected_at.utc.iso8601(6)
      )
    end

    def event_id(event)
      event&.fetch("event_id", nil)
    end

    def timestamp(value)
      value&.utc&.iso8601(6)
    end
  end
end
