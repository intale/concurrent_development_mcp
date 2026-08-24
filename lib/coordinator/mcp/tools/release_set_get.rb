# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ReleaseSetGet < QueryTool
        tool_name "release_set_get"
        title "Get an available release set"
        description "Read the latest available ReleaseSet projection without a freshness gate."
        input_schema Schemas.release_set_get
        query "queries.release_set_get"
      end
    end
  end
end
