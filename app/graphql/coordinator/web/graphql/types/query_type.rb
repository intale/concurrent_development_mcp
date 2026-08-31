# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class QueryType < BaseObject
    graphql_name "Query"
    description "Read-only access to the latest available coordination projections."

    field :projects, ProjectConnectionType, null: false, connection: false do
      description "List projects in one exact caller-chosen scope in stable Repository-ID order."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :scope, String, required: true
    end

    field :project_coordination, ProjectCoordinationType, null: true do
      description "Latest available coordination facts for one registered project."
      argument :blocking, Boolean, required: false
      argument :change_sets_after, String, required: false
      argument :dependencies_after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :presentation_statuses, [ CoordinationPresentationStatusEnum ], required: false
      argument :repository_id, ID, required: true
      argument :work_item_sort, WorkItemSortEnum, required: false, default_value: "work_item_id_asc"
      argument :work_items_after, String, required: false
    end

    def projects(scope:, first:, after: nil)
      query = Coordinator::Read::Queries::RepositoryList.new.call(
        scope:,
        after_repository_id: Coordinator::Web::Graphql::ProjectCursor.decode(after),
        limit: first
      ).value!
      raise_query_error(query) unless query.status == "ok"

      page = query.data.page
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_repository_id &&
            Coordinator::Web::Graphql::ProjectCursor.encode(page.next_repository_id),
          has_next_page: page.has_more
        }
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    end

    def project_coordination(
      repository_id:,
      first:,
      work_item_sort:,
      blocking: nil,
      change_sets_after: nil,
      dependencies_after: nil,
      presentation_statuses: nil,
      work_items_after: nil
    )
      dashboard = Coordinator::Read::Web::Queries::CoordinationDashboard.new.call(
        repository_id:,
        first:,
        change_set_offset: Coordinator::Web::Graphql::DashboardCursor.decode(
          change_sets_after,
          "change-sets"
        ),
        work_item_offset: Coordinator::Web::Graphql::DashboardCursor.decode(
          work_items_after,
          "work-items"
        ),
        dependency_offset: Coordinator::Web::Graphql::DashboardCursor.decode(
          dependencies_after,
          "dependencies"
        ),
        presentation_statuses: presentation_statuses || [],
        work_item_sort:,
        blocking:
      )
      return unless dashboard

      {
        project: dashboard.project,
        change_sets: connection(dashboard.change_sets, "change-sets"),
        work_items: connection(dashboard.work_items, "work-items"),
        dependencies: connection(dashboard.dependencies, "dependencies")
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    private

    def connection(page, kind)
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_offset && Coordinator::Web::Graphql::DashboardCursor.encode(kind, page.next_offset),
          has_next_page: page.has_more
        }
      }
    end

    def raise_query_error(result)
      raise GraphQL::ExecutionError.new(
        result.data.message,
        extensions: { code: result.data.code.upcase, details: result.data.details }
      )
    end
  end
end
