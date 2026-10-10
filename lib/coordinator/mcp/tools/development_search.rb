# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentSearch < Coordinator::Mcp::QueryTool
    tool_name "development_search"
    title "Search available development context"
    description "Read-only bounded literal pattern search over explicit projection fields. " \
      "Use contains, starts_with, ends_with or whole-field equals, optional case sensitivity, within-field AND/OR/NOT and cross-field OR only. " \
      "Values need at least 3 characters and every alternative a positive three-alphanumeric-character anchor. " \
      "No regex, wildcards, linguistic matching, SQL, client hashing or Base64. Exact filters intersect. " \
      "Returns native updated_at order, plain excerpts, real scalar paths and typed retrieval actions. " \
      "Available projections may lag; live keyset pages are not snapshots. Budget failure returns no partial results: narrow and retry. " \
      "A trigram anchor and branch limits do not guarantee an index plan or constant query time."
    input_schema Coordinator::Mcp::Schemas.development_search
    query "queries.development_search"

    class << self
      private

      def response(result, error: false)
        rendered = super
        return rendered if JSON.generate(rendered.to_h).bytesize <= Coordinator::Read::Search::Limits::RESPONSE_BYTES

        super(Coordinator::Mcp::ResultV1.new(status: "limit_reached",
          summary: "Search response exceeds the byte limit; reduce the page size and retry.",
          command_id: nil, receipt: nil, context_token: nil,
          data: Coordinator::Mcp::ResultV1::DomainError.new(code: "search_response_limit",
            message: "Rendered search response exceeds the byte limit", details: {}),
          warnings: [], next_actions: []), error:)
      end
    end
  end
end
