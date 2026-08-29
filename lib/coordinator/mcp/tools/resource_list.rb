# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ResourceList < QueryTool
        tool_name "resource_list"
        title "List available Repository Resources"
        description <<~TEXT.squish
          Discover the latest available projected Resources for one exact Repository in bounded UUID order.
          Optional kind and lifecycle filters apply only to the available projection; no write-store freshness check runs.
        TEXT
        input_schema Schemas.resource_list
        query "queries.resource_list"
      end
    end
  end
end
