# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class RepositoryList < QueryTool
        tool_name "repository_list"
        title "List repositories in an exact coordination scope"
        description <<~TEXT.squish
          Discover available projected Repository registrations for one exact caller-chosen scope in bounded canonical-ID
          order. Returned paths and remotes are attributed registration metadata; the server never accesses them, and the
          projection remains available while it catches up with writes.
        TEXT
        input_schema Schemas.repository_list
        query "queries.repository_list"
      end
    end
  end
end
