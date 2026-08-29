# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillAssetGet < QueryTool
        tool_name "skill_asset_get"
        title "Get available AI Skill asset content"
        description <<~TEXT.squish
          Read one passive asset from an exact scoped Skill revision. Valid UTF-8 is returned as text;
          canonical Base64 is returned only for explicitly binary content.
        TEXT
        input_schema Schemas.skill_asset_get
        query "queries.skill_asset_get"
      end
    end
  end
end
