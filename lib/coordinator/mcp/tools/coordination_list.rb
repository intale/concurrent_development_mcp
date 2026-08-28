# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CoordinationList < QueryTool
        tool_name "coordination_list"
        title "Discover available project coordination"
        description <<~TEXT.squish
          Starting from one exact caller/user-chosen project scope, list bounded current or recent projected
          ChangeSets and return complete coord_context continuation actions. Canonical coordination IDs are
          globally namespaced; reusable human labels are not primary identity. Available results may lag and
          never authorize a write command. This is coordination discovery, not Task enumeration.
        TEXT
        input_schema Schemas.coordination_list
        query "queries.coordination_list"
      end
    end
  end
end
