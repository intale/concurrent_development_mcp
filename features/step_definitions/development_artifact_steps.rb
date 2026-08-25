# frozen_string_literal: true

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
