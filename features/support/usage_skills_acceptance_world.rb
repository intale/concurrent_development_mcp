# frozen_string_literal: true

module UsageSkillsAcceptanceWorld
  def product_usage_catalog
    Coordinator::Mcp::UsageSkills::Catalog
  end

  def install_product_usage_skills
    start_live_subscriptions
    run_product_usage_installer
    assert_acceptance(@usage_installer_status.success?, "Usage Skill installation failed: #{@usage_installer_output}")
  end

  def run_product_usage_installer(environment = {})
    @usage_installer_output = IO.popen([ environment, Rails.root.join("bin/install-mcp-skills").to_s, err: [ :child, :out ] ], &:read)
    @usage_installer_status = $?
  end

  def retrieve_product_usage_skills
    product_usage_catalog.all.to_h do |definition|
      document = await_read_model("usage Skill #{definition.name}") do
        payload = call_tool("skill_get", { name: definition.name, scope: product_usage_catalog::SCOPE }).dig("result", "structuredContent")
        skill = payload.dig("data", "skill")
        [ skill && skill.fetch("instructions") == definition.instructions, skill ]
      end
      [ definition.name, document ]
    end
  end
end

World(UsageSkillsAcceptanceWorld)
