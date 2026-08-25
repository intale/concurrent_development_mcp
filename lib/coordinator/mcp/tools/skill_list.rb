# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillList < QueryTool
        tool_name "skill_list"
        title "List available scoped AI Skills"
        description "Discover observed Skill revisions in bounded order with optional exact name and scope filters."
        input_schema Schemas.skill_list
        query "queries.skill_list"
      end
    end
  end
end
