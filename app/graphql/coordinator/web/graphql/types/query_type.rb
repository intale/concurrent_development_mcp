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

    private

    def raise_query_error(result)
      raise GraphQL::ExecutionError.new(
        result.data.message,
        extensions: { code: result.data.code.upcase, details: result.data.details }
      )
    end
  end
end
