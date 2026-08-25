# frozen_string_literal: true

When("a clean agent asks the MCP endpoint how to migrate development memory") do
  @migration_discovery = mcp_request(method: "server/discover", params: {})
  @migration_tools = mcp_request(method: "tools/list", params: {})
    .dig("result", "tools")
end

Then("the endpoint assigns project discovery to the agent without assuming paths or runtimes") do
  instructions = @migration_discovery.dig("result", "instructions").squish
  assert_acceptance(instructions.include?("client's own available capabilities"), "Client discovery guidance")
  assert_acceptance(instructions.include?("never by a server-prescribed directory layout"), "Layout guidance")
  assert_acceptance(instructions.include?("The coordinator cannot read caller paths"), "Server boundary guidance")

  surface = JSON.generate(
    @migration_tools.select do |tool|
      %w[
        skill_publish skill_publish_batch development_artifact_capture
        development_artifact_capture_batch development_artifact_relation_declare
        development_artifact_relation_declare_batch
      ].include?(tool.fetch("name"))
    end
  )
  %w[.build .to_review source_root Rails.root python ruby node].each do |assumption|
    assert_acceptance(!surface.include?(assumption), "Migration surface prescribes #{assumption}")
  end
end

Then("the import-capable schemas require exact content and caller-owned provenance") do
  artifact = @migration_tools.find { _1.fetch("name") == "development_artifact_capture" }
  skill = @migration_tools.find { _1.fetch("name") == "skill_publish" }
  artifact_schema = artifact.fetch("inputSchema")

  assert_acceptance(
    artifact_schema.dig("properties", "kind", "description").include?("choose from meaning"),
    "Semantic Artifact classification"
  )
  assert_acceptance(
    artifact_schema.dig("properties", "content", "properties", "text", "description").include?("Exact UTF-8"),
    "Exact Artifact content"
  )
  assert_acceptance(
    artifact_schema.dig("properties", "source", "properties", "locator", "description").include?(
      "server never dereferences it"
    ),
    "Caller-owned locator"
  )
  assert_acceptance(
    skill.dig("inputSchema", "properties", "assets", "description").include?("Complete passive asset snapshot"),
    "Complete Skill asset snapshot"
  )
end

When("the agent captures documentation and web-search Development Artifacts") do
  @documentation_text = "Artifact repository contract\n"
  @artifact_outcomes = [
    capture_artifact_task(
      command_id: "cmd-cuc-artifact-doc",
      title: "Artifact contract",
      kind: "documentation",
      labels: %w[evidence imported],
      locator: "docs/artifacts.md",
      source_kind: "local_file",
      content: { encoding: "utf-8", media_type: "text/markdown", text: @documentation_text }
    ),
    capture_artifact_task(
      command_id: "cmd-cuc-artifact-search",
      title: "Search evidence",
      kind: "web_research",
      labels: %w[evidence imported web],
      locator: "search:artifact repository",
      source_kind: "web_search",
      content: { encoding: "utf-8", media_type: "application/json", text: "{\"result\":\"found\"}\n" }
    )
  ]
end

Then("both Artifact Tasks complete with different immutable IDs") do
  assert_acceptance(@artifact_outcomes.all? { _1.fetch("status") == "ok" }, "Capture outcomes")
  @artifact_ids = @artifact_outcomes.map { _1.dig("data", "artifact_id") }
  assert_acceptance_equal(2, @artifact_ids.uniq.length, "Artifact identities")
end

When("the Development Artifact facts reach the read side") do
  @artifact_ids.each { project_artifact(_1) }
end

Then("listing the shared evidence labels returns both Artifacts") do
  page = call_tool(
    "development_artifact_list",
    { scope: "project:acceptance", labels: %w[evidence imported], limit: 20 }
  ).dig("result", "structuredContent", "data", "page")
  assert_acceptance_equal(
    @artifact_ids.sort,
    page.fetch("items").map { _1.fetch("artifact_id") }.sort,
    "Filtered Artifact IDs"
  )
end

Then("Artifact metadata excludes content bytes") do
  metadata = artifact_view(@artifact_ids.first)
  assert_acceptance(!metadata.to_s.include?(@documentation_text), "Metadata embedded content bytes")
end

Then("focused Artifact content returns the exact documentation text as passive data") do
  content = artifact_content(@artifact_ids.first)
  assert_acceptance_equal(
    @documentation_text,
    content.dig("data", "content", "text"),
    "Documentation content"
  )
  assert_acceptance(content.fetch("warnings").sole.include?("passive data"), "Passive warning")
end

When("the agent captures two binary profile versions from one source") do
  @profile_contents = [ "\x00\x01".b, "\x00\x02".b ]
  @profile_outcomes = @profile_contents.each_with_index.map do |bytes, index|
    capture_artifact_task(
      command_id: "cmd-cuc-profile-#{index}",
      title: "Profile #{index}",
      kind: "performance_profile",
      labels: %w[profile binary],
      locator: "tmp/profile.dump",
      source_kind: "local_file",
      content: {
        encoding: "binary",
        media_type: "application/octet-stream",
        base64: [ bytes ].pack("m0")
      }
    )
  end
  @profile_ids = @profile_outcomes.map { _1.dig("data", "artifact_id") }
end

Then("the changed profile has a different immutable Artifact ID") do
  assert_acceptance_equal(2, @profile_ids.uniq.length, "Changed profile identities")
end

When("the agent declares that the changed profile supersedes the earlier profile") do
  task_id = submit_and_execute(
    "development_artifact_relation_declare",
    command_id: "cmd-cuc-profile-supersedes",
    actor: { kind: "agent", id: "artifact-agent" },
    source_artifact_id: @profile_ids.last,
    relation: "supersedes",
    target: { kind: "artifact", id: @profile_ids.first },
    attributes: {}
  )
  @profile_relation_outcome = task_request("tasks/get", task_id)
    .dig("result", "result", "structuredContent")
end

When("the binary Artifact facts reach the read side") do
  @profile_ids.each { project_artifact(_1) }
end

Then("the changed profile exposes the supersession relationship") do
  relationship = artifact_view(@profile_ids.last).dig("data", "artifact", "relationships").sole
  assert_acceptance_equal("supersedes", relationship.fetch("relation"), "Relationship kind")
  assert_acceptance_equal(
    @profile_ids.first,
    relationship.dig("target", "id"),
    "Relationship target"
  )
end

Then("its exact Base64 content is available but never executed") do
  payload = artifact_content(@profile_ids.last)
  assert_acceptance_equal(
    [ @profile_contents.last ].pack("m0"),
    payload.dig("data", "content", "base64"),
    "Binary profile content"
  )
  assert_acceptance(payload.fetch("warnings").sole.include?("passive data"), "Passive warning")
end
