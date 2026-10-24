# frozen_string_literal: true

Given("the built-in server usage Skills are available") do
  response = call_tool("skill_list", {})
  assert_acceptance_equal("ok", response.dig("result", "structuredContent", "status"), "Static catalog availability")
end

Given("a project Skill has the same name as the product entry guide") do
  start_live_subscriptions
  submit_and_execute(
    "skill_publish", command_id: "usage-existing-project-skill", actor: { kind: "agent", id: "usage-client" },
    name: product_usage_catalog::ENTRY_SKILL, scope: "project:unrelated", expected_revision: 0,
    description: "Project-specific rules", instructions: "Preserve this project's own instructions.", assets: []
  )
end

When("the client lists server Skills without a scope") do
  @usage_default_page = call_tool("skill_list", {}).dig("result", "structuredContent", "data", "page")
end

Then("every public function belongs to one discoverable capability guide") do
  tools = mcp_request(method: "tools/list", params: {}).dig("result", "tools").map { _1.fetch("name") }.sort
  documented = @usage_default_page.fetch("items").flat_map { _1.fetch("tools") }.sort
  assert_acceptance_equal(tools, documented, "Complete function coverage with no duplicates")
end

Then("discovery routes a new client to the product getting-started Skill") do
  discovery = mcp_request(method: "server/discover", params: {}).fetch("result")
  instructions = discovery.fetch("instructions")
  assert_acceptance(instructions.bytesize < 2_000, "Discovery should be concise")
  assert_acceptance(instructions.include?(product_usage_catalog::ENTRY_SKILL), "Entry Skill route")
  assert_acceptance(instructions.include?(product_usage_catalog::SCOPE), "Exact product scope")
end

Then("the client can retrieve every built-in guide immediately") do
  documents = retrieve_product_usage_skills
  assert_acceptance_equal(product_usage_catalog.all.map(&:name).sort, documents.keys.sort, "Static guide identities")
  product_usage_catalog.all.each do |definition|
    document = documents.fetch(definition.name)
    assert_acceptance_equal("server", document.fetch("source"), "Static source")
    assert_acceptance_equal(product_usage_catalog::RELEASE, document.fetch("revision"), "Application bundle revision")
    assert_acceptance_equal(definition.instructions, document.fetch("instructions"), "Shipped instructions")
    assert_acceptance(!document.key?("published"), "No fabricated publication event")
  end
end

Then("the project Skill is unchanged") do
  document = await_read_model("unrelated project guide") do
    skill = call_tool("skill_get", { name: product_usage_catalog::ENTRY_SKILL, scope: "project:unrelated" })
      .dig("result", "structuredContent", "data", "skill")
    [ !skill.nil?, skill ]
  end
  assert_acceptance_equal("Preserve this project's own instructions.", document.fetch("instructions"), "Project entity content")
  assert_acceptance_equal(1, document.fetch("revision"), "Project entity revision")
end

When("the client pages through server Skills two at a time") do
  @usage_paged_names = []
  cursor = nil
  loop do
    page = call_tool("skill_list", { limit: 2, after_skill_id: cursor }).dig("result", "structuredContent", "data", "page")
    @usage_paged_names.concat(page.fetch("items").map { _1.fetch("name") })
    break unless page.fetch("has_more")

    cursor = page.fetch("next_skill_id")
  end
end

Then("every built-in guide appears once in deterministic name order") do
  assert_acceptance_equal(product_usage_catalog.all.map(&:name).sort, @usage_paged_names, "Static pagination")
end

Then("an exact server Skill name filter selects one guide") do
  page = call_tool("skill_list", { name: product_usage_catalog::ENTRY_SKILL }).dig("result", "structuredContent", "data", "page")
  assert_acceptance_equal([ product_usage_catalog::ENTRY_SKILL ], page.fetch("items").map { _1.fetch("name") }, "Exact filter")
end

When("the client requests unknown built-in content and a different bundle revision") do
  @missing_usage_results = [
    call_tool("skill_get", { name: "unknown-guide", scope: product_usage_catalog::SCOPE }),
    call_tool("skill_get", { name: product_usage_catalog::ENTRY_SKILL, scope: product_usage_catalog::SCOPE, revision: product_usage_catalog::RELEASE + 1 }),
    call_tool("skill_asset_get", { name: product_usage_catalog::ENTRY_SKILL, scope: product_usage_catalog::SCOPE, path: "missing.md" })
  ].map { _1.dig("result", "structuredContent") }
end

Then("each request returns a typed static not-found outcome") do
  @missing_usage_results.each do |result|
    assert_acceptance_equal("not_found", result.fetch("status"), "Static not-found")
    assert_acceptance(result.dig("data", "code").start_with?("server_skill"), "Static error identity")
  end
end
