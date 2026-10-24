# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillList < QueryTool
        tool_name "skill_list"
        title "List server usage Skills or scoped Skill entities"
        description "Omit scope, or use mcp:concurrent-development-coordinator, to discover static built-in guides " \
                    "covering every server function without database access. Each lists its tools. " \
                    "An explicit other scope lists stored project Skill entities from available projections; " \
                    "source: stored also supports entity discovery across scopes. " \
                    "Use exact name filters and next_skill_id pagination; no installation is required."
        input_schema Schemas.skill_list
        query "queries.skill_list"

        def self.call(server_context: nil, **arguments)
          if arguments[:source] == "stored" || (arguments[:source] != "server" && arguments[:scope] && arguments[:scope] != UsageSkills::Catalog::SCOPE)
            return invoke(query, arguments.except(:source))
          end

          response(UsageSkills::Query.new.list(arguments))
        end
      end
    end
  end
end
