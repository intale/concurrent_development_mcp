# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillAssetGet < QueryTool
        tool_name "skill_asset_get"
        title "Get available AI Skill asset content"
        description "Read one passive Base64 asset from the latest observed revision of an exact scoped Skill."
        input_schema Schemas.skill_asset_get
        query "queries.skill_asset_get"
      end
    end
  end
end
