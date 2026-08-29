# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ResourceGet < QueryTool
        tool_name "resource_get"
        title "Get an available Resource lifecycle"
        description <<~TEXT.squish
          Read the latest available projected identity and lifecycle for one server-owned Resource UUID.
          The view may lag authoritative writes and is still served without freshness checks or availability gates.
        TEXT
        input_schema Schemas.resource_get
        query "queries.resource_get"
      end
    end
  end
end
