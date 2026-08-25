# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillGet < QueryTool
        tool_name "skill_get"
        title "Get an available scoped AI Skill"
        description "Read the latest observed revision and asset manifest for one exact, case-sensitive Skill name and scope."
        input_schema Schemas.skill_get
        query "queries.skill_get"
      end
    end
  end
end
