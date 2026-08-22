# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class GuidanceGet < QueryTool
        tool_name "guidance_get"
        title "Get guidance evidence"
        description "Read the available projected guidance evidence for one message without a freshness gate."
        input_schema Schemas.guidance_get
        query "queries.guidance_get"
      end
    end
  end
end
