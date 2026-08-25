# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillPublish < MutationTool
        tool_name "skill_publish"
        title "Publish a scoped AI skill revision"
        description "Publish one complete immutable skill and asset revision under an exact user-chosen name and scope. Stored assets are never executed."
        input_schema Schemas.skill_publish
        operation "operations.submit_publish_skill_revision_task"
      end
    end
  end
end
