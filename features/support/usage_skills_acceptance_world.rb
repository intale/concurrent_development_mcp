# frozen_string_literal: true

module UsageSkillsAcceptanceWorld
  def product_usage_catalog
    Coordinator::Mcp::UsageSkills::Catalog
  end

  def retrieve_product_usage_skills
    product_usage_catalog.all.to_h do |definition|
      payload = call_tool("skill_get", { name: definition.name, scope: product_usage_catalog::SCOPE })
        .dig("result", "structuredContent", "data", "skill")
      [ definition.name, payload ]
    end
  end
end

World(UsageSkillsAcceptanceWorld)
