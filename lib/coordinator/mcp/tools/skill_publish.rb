# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillPublish < MutationTool
        tool_name "skill_publish"
        title "Publish a scoped AI skill revision"
        description "Publish one caller-discovered reusable instruction set and all passive support assets as a complete immutable revision under an exact user-chosen name and scope. The server never reads a Skill directory or executes an asset."
        input_schema Schemas.skill_publish
        operation "operations.submit_publish_skill_revision_task"
      end
    end
  end
end
