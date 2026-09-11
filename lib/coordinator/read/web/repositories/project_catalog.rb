# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class ProjectCatalog
    include EventTimePagination

    SEARCH_SQL = <<~SQL.squish.freeze
      repositories.scope ILIKE :pattern ESCAPE E'\\\\'
      OR repositories.display_name ILIKE :pattern ESCAPE E'\\\\'
      OR EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(repositories.paths) AS project_path(value)
        WHERE project_path.value ILIKE :pattern ESCAPE E'\\\\'
      )
    SQL

    def initialize(project_reference: Coordinator::Read::Web::ProjectReference.new)
      @project_reference = project_reference
    end

    def page(query)
      scope_rows, has_more = project_scopes(query)
      scopes = scope_rows.map(&:scope)
      summaries = summaries_for(scopes, query.repositories_first)

      Coordinator::Read::Web::ProjectCatalogV1::ProjectPage.new(
        items: scopes.map { summaries.fetch(_1) },
        next_scope: has_more ? scopes.last : nil,
        next_updated_at: has_more ? event_time(scope_rows.last) : nil,
        has_more:
      )
    end

    def overview(query)
      relation = Coordinator::Read::Repository.where(scope: query.scope)
      repository_count = relation.count
      return if repository_count.zero?

      display_label = overview_display_label(relation, query.scope, repository_count)
      records, has_more = event_time_page(
        relation:,
        id_column: :repository_id,
        after_updated_at: query.after_updated_at,
        after_id: query.after_repository_id,
        limit: query.repositories_first
      )
      Coordinator::Read::Web::ProjectCatalogV1::ProjectOverview.new(
        project_ref: query.project_ref,
        scope: query.scope,
        display_label:,
        repository_count:,
        repositories: repository_page(records, query.repositories_first, repository_count, has_more:)
      )
    end

    private

    def project_scopes(query)
      relation = Coordinator::Read::Repository.all
      relation = apply_search(relation, query.search) if query.search
      relation = relation.select(:scope, "MAX(updated_at) AS updated_at").group(:scope)
      direction = query.sort == "oldest_first" ? :asc : :desc
      comparator = direction == :asc ? ">" : "<"
      if query.after_scope
        relation = relation.having(
          "MAX(updated_at) #{comparator} :updated_at OR " \
          "(MAX(updated_at) = :updated_at AND scope #{comparator} :scope)",
          updated_at: query.after_updated_at,
          scope: query.after_scope
        )
      end
      rows = relation
        .order(Arel.sql("MAX(updated_at) #{direction.to_s.upcase}, scope #{direction.to_s.upcase}"))
        .limit(query.first + 1)
        .to_a
      [ rows.first(query.first), rows.length > query.first ]
    end

    def apply_search(relation, search)
      escaped = ActiveRecord::Base.sanitize_sql_like(search)
      relation.where(SEARCH_SQL, pattern: "%#{escaped}%")
    end

    def summaries_for(scopes, repositories_first)
      return {} if scopes.empty?

      records = preview_records(scopes, repositories_first).group_by(&:scope)
      scopes.to_h do |scope|
        project_records = records.fetch(scope)
        repository_count = project_records.first.attributes.fetch("project_repository_count").to_i
        page = repository_page(project_records, repositories_first, repository_count)
        [
          scope,
          Coordinator::Read::Web::ProjectCatalogV1::ProjectSummary.new(
            project_ref: @project_reference.encode(scope:),
            scope:,
            display_label: summary_display_label(scope, page, repository_count),
            repository_count:,
            repositories: page
          )
        ]
      end
    end

    def preview_records(scopes, repositories_first)
      ranked = Coordinator::Read::Repository.where(scope: scopes).select(
        "repositories.*",
        "COUNT(*) OVER (PARTITION BY scope) AS project_repository_count",
        "ROW_NUMBER() OVER (PARTITION BY scope ORDER BY updated_at DESC, repository_id DESC) " \
        "AS project_member_position"
      )
      Coordinator::Read::Repository
        .from("(#{ranked.to_sql}) repositories")
        .where("project_member_position <= ?", repositories_first + 1)
        .order(:scope, updated_at: :desc, repository_id: :desc)
        .to_a
    end

    def repository_page(records, limit, total_count, has_more: records.length > limit)
      page_records = records.first(limit)
      Coordinator::Read::Web::ProjectCatalogV1::RepositoryPage.new(
        items: page_records.map { repository_member(_1) },
        next_repository_id: has_more ? page_records.last.repository_id : nil,
        next_updated_at: has_more ? event_time(page_records.last) : nil,
        has_more:,
        total_count:
      )
    end

    def repository_member(record)
      Coordinator::Read::Web::ProjectCatalogV1::RepositoryMember.new(
        repository_id: record.repository_id,
        display_name: record.display_name,
        paths: record.paths,
        remotes: record.remotes,
        registered_at: record.registered_at_domain.utc.iso8601(6)
      )
    end

    def summary_display_label(scope, page, repository_count)
      return scope unless repository_count == 1

      page.items.first.display_name || scope
    end

    def overview_display_label(relation, scope, repository_count)
      return scope unless repository_count == 1

      relation.pick(:display_name) || scope
    end
  end
end
