# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillGet < QueryTool
        tool_name "skill_get"
        title "Read a server usage Skill or scoped Skill entity"
        description "In mcp:concurrent-development-coordinator, read static built-in capability instructions directly " \
                    "from the running application, without databases, Tasks or installation. revision pins the bundle. " \
                    "In another exact scope, read the latest available projected Skill entity and its asset manifest. " \
                    "An agent chooses how to use the returned instructions."
        input_schema Schemas.skill_get
        query "queries.skill_get"

        def self.call(server_context: nil, **arguments)
          return super unless arguments[:scope] == UsageSkills::Catalog::SCOPE

          response(UsageSkills::Query.new.get(arguments))
        end
      end
    end
  end
end
