# frozen_string_literal: true

Given("a project Skill has the same name as the product entry guide") do
  start_live_subscriptions
  submit_and_execute(
    "skill_publish", command_id: "usage-existing-project-skill", actor: { kind: "agent", id: "usage-client" },
    name: product_usage_catalog::ENTRY_SKILL, scope: "project:unrelated", expected_revision: 0,
    description: "Project-specific rules", instructions: "Preserve this project's own instructions.", assets: []
  )
end

Given("the product usage Skills are installed") do
  install_product_usage_skills
  @original_usage_documents = retrieve_product_usage_skills
end

When("the operator installs the bundled product usage Skills") do
  install_product_usage_skills
end

When("the operator installs the bundled product usage Skills again") do
  install_product_usage_skills
end

Then("discovery routes a new client to the product getting-started Skill") do
  discovery = mcp_request(method: "server/discover", params: {}).fetch("result")
  instructions = discovery.fetch("instructions")
  assert_acceptance(instructions.bytesize < 2_000, "Discovery should be concise")
  assert_acceptance(instructions.include?(product_usage_catalog::ENTRY_SKILL), "Entry Skill route")
  assert_acceptance(instructions.include?(product_usage_catalog::SCOPE), "Exact product scope")
end

Then("the client can retrieve every bundled guide through skill_get") do
  documents = retrieve_product_usage_skills
  assert_acceptance_equal(product_usage_catalog.all.map(&:name).sort, documents.keys.sort, "Installed guide identities")
  documents.each_value { assert_acceptance_equal(1, _1.fetch("revision"), "Initial product revision") }
  page = call_tool("skill_list", { scope: product_usage_catalog::SCOPE, limit: 20 }).dig("result", "structuredContent", "data", "page")
  assert_acceptance_equal(documents.keys.sort, page.fetch("items").map { _1.fetch("name") }.sort, "Discoverable guide names")
end

Then("the project Skill is unchanged") do
  document = await_read_model("unrelated project guide") do
    skill = call_tool("skill_get", { name: product_usage_catalog::ENTRY_SKILL, scope: "project:unrelated" })
      .dig("result", "structuredContent", "data", "skill")
    [ !skill.nil?, skill ]
  end
  assert_acceptance_equal("Preserve this project's own instructions.", document.fetch("instructions"), "Unrelated project instructions")
  assert_acceptance_equal(1, document.fetch("revision"), "Unrelated project revision")
end

Then("every publication reports the existing revision without replacing a Skill") do
  product_usage_catalog.all.each do |definition|
    assert_acceptance(@usage_installer_output.include?("#{definition.name}: existing revision 1"), @usage_installer_output)
  end
  documents = retrieve_product_usage_skills
  assert_acceptance_equal(
    @original_usage_documents.transform_values { _1.values_at("skill_id", "revision") },
    documents.transform_values { _1.values_at("skill_id", "revision") }, "Unchanged Skill identities/revisions"
  )
end

When("the operator publishes an updated knowledge-management guide") do
  original = product_usage_catalog.all.find { _1.name == "coordinator-knowledge-management" }
  @updated_usage_definition = Coordinator::Mcp::UsageSkills::Definition.new(
    original.to_h.merge(instructions: original.instructions + "\nUpdated package guidance.\n")
  )
  task_id = submit_and_execute(
    "skill_publish", command_id: "usage-updated-knowledge-guide", actor: { kind: "agent", id: "usage-package-editor" },
    name: original.name, scope: product_usage_catalog::SCOPE,
    expected_revision: @original_usage_documents.fetch(original.name).fetch("revision"),
    description: original.description, instructions: @updated_usage_definition.instructions, assets: []
  )
  @usage_update_result = call_tool("task_get", { task_id: }).dig("result", "structuredContent", "result", "structuredContent")
end

Then("the client retrieves the updated guide without retaining superseded read revisions") do
  assert_acceptance_equal("committed", @usage_update_result.dig("completion", "effects"), "Updated publication")
  assert_acceptance_equal(2, @usage_update_result.dig("data", "revision"), "Updated revision")
  document = await_read_model("updated usage guide") do
    skill = call_tool("skill_get", { name: @updated_usage_definition.name, scope: product_usage_catalog::SCOPE })
      .dig("result", "structuredContent", "data", "skill")
    [ skill && skill.fetch("revision") == 2, skill ]
  end
  assert_acceptance_equal(@updated_usage_definition.instructions, document.fetch("instructions"), "Updated instructions")
  historical = call_tool("skill_get", { name: @updated_usage_definition.name, scope: product_usage_catalog::SCOPE, revision: 1 })
    .dig("result", "structuredContent")
  assert_acceptance_equal("not_found", historical.fetch("status"), "Superseded read revision is not retained")
end

Then("the other product guide revisions are unchanged") do
  @original_usage_documents.except(@updated_usage_definition.name).each do |name, original|
    document = call_tool("skill_get", { name:, scope: product_usage_catalog::SCOPE }).dig("result", "structuredContent", "data", "skill")
    assert_acceptance_equal(original.values_at("skill_id", "revision"), document.values_at("skill_id", "revision"), "Other guide identity/revision")
  end
end

Given("no usage Skill Task workers are running") do
  stop_live_subscriptions
  @usage_pending_run_id = SecureRandom.uuid_v7
end

When("the product installer times out on its first pending publication") do
  run_product_usage_installer("MCP_USAGE_SKILL_RUN_ID" => @usage_pending_run_id, "MCP_USAGE_SKILL_TIMEOUT_SECONDS" => "0")
  assert_acceptance(!@usage_installer_status.success?, "Pending install must report its unfinished state")
  assert_acceptance(@usage_installer_output.include?("still working"), @usage_installer_output)
  @usage_pending_task_id = @usage_installer_output[/Task ([0-9a-f-]{36})/, 1]
  assert_acceptance(@usage_pending_task_id, "Printed pending Task handle")
end

When("the unchanged run is resumed while workers are still stopped") do
  run_product_usage_installer("MCP_USAGE_SKILL_RUN_ID" => @usage_pending_run_id, "MCP_USAGE_SKILL_TIMEOUT_SECONDS" => "0")
  assert_acceptance(!@usage_installer_status.success?, "Resumed pending install must report its unfinished state")
  @usage_resumed_task_id = @usage_installer_output[/Task ([0-9a-f-]{36})/, 1]
end

Then("it reports the same working Task without cancelling it") do
  assert_acceptance_equal(@usage_pending_task_id, @usage_resumed_task_id, "Recovered Task handle")
  task = call_tool("task_get", { task_id: @usage_pending_task_id }).dig("result", "structuredContent")
  assert_acceptance_equal("working", task.fetch("status"), "Retained working state")
end

When("the usage Skill workers start") do
  start_live_subscriptions
end

Then("the original publication eventually becomes a retrievable Skill") do
  task = await_task_terminal(@usage_pending_task_id)
  assert_acceptance_equal(false, task.dig("result", "result", "isError"), "Original publication outcome")
  first = product_usage_catalog.all.first
  document = await_read_model("resumed entry guide") do
    skill = call_tool("skill_get", { name: first.name, scope: product_usage_catalog::SCOPE }).dig("result", "structuredContent", "data", "skill")
    [ skill && skill.fetch("instructions") == first.instructions, skill ]
  end
  assert_acceptance_equal(1, document.fetch("revision"), "Only one Skill revision")
end

Given("an authoritative product guide exists without its read projection") do
  stop_read_model_subscriptions
  first = product_usage_catalog.all.first
  @prior_usage_instructions = "Previously published authoritative guide."
  submit_and_execute(
    "skill_publish", command_id: "usage-stale-guide", actor: { kind: "agent", id: "prior-usage-publisher" },
    name: first.name, scope: product_usage_catalog::SCOPE, expected_revision: 0,
    description: "Existing authoritative publication", instructions: @prior_usage_instructions, assets: []
  )
  payload = call_tool("skill_get", { name: first.name, scope: product_usage_catalog::SCOPE }).dig("result", "structuredContent")
  assert_acceptance_equal("not_found", payload.fetch("status"), "Available lagging Skill view")
end

When("the installer exhausts its bounded revision-conflict attempts") do
  run_product_usage_installer
  assert_acceptance(!@usage_installer_status.success?, "Stale installation must report its conflict")
  assert_acceptance(@usage_installer_output.include?("skill_revision_conflict"), @usage_installer_output)
end

Then("the updater restores its bundled snapshot as the next revision") do
  name = @updated_usage_definition.name
  assert_acceptance(@usage_installer_output.include?("#{name}: published revision 3"), @usage_installer_output)
  original = product_usage_catalog.all.find { _1.name == name }
  document = await_read_model("updated bundled snapshot") do
    skill = call_tool("skill_get", { name:, scope: product_usage_catalog::SCOPE }).dig("result", "structuredContent", "data", "skill")
    [ skill && skill.fetch("revision") == 3, skill ]
  end
  assert_acceptance_equal(original.instructions, document.fetch("instructions"), "Reconciled bundle content")
end

Then("it reports the conflict without replacing the authoritative guide") do
  first = product_usage_catalog.all.first
  document = await_read_model("retained original product guide") do
    skill = call_tool("skill_get", { name: first.name, scope: product_usage_catalog::SCOPE }).dig("result", "structuredContent", "data", "skill")
    [ !skill.nil?, skill ]
  end
  assert_acceptance_equal(1, document.fetch("revision"), "Original revision after denied update")
  assert_acceptance_equal(@prior_usage_instructions, document.fetch("instructions"), "Original authoritative content")
end
