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
  skill_asset = skill.dig("inputSchema", "properties", "assets", "items")
  skill_asset_properties = skill_asset.fetch("properties")
  assert_acceptance(skill_asset_properties.key?("content"), "Skill asset semantic content union")
  assert_acceptance(!skill_asset_properties.key?("content_base64"), "Skill asset legacy Base64 field")
  assert_acceptance(
    skill_asset_properties.dig("content", "properties", "text", "description").include?(
      "no client-side Base64 or digest"
    ),
    "Text-first Skill guidance"
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

When("the agent captures an external reference to {string}") do |url|
  @external_reference_url = url
  @external_reference_outcome = capture_artifact_task(
    command_id: "cmd-cuc-artifact-external-reference",
    title: "External reference",
    kind: "external_reference",
    labels: %w[external reference],
    locator: url,
    source_kind: "web_page",
    content: { encoding: "utf-8", media_type: "text/uri-list", text: "#{url}\n" }
  )
  @external_reference_id = @external_reference_outcome.dig("data", "artifact_id")
end

When("the external-reference Artifact fact reaches the read side") do
  project_artifact(@external_reference_id)
end

Then("its persisted and projected content is exactly the URL followed by one newline") do
  event_content = artifact_events(@external_reference_id).sole.data.dig("artifact", "content")
  projected = artifact_content(@external_reference_id).dig("data", "content")
  expected = "#{@external_reference_url}\n"
  assert_acceptance_equal(expected, event_content.fetch("text"), "Persisted reference")
  assert_acceptance_equal(expected, projected.fetch("text"), "Projected reference")
end

Then("the external-reference content contains no binary or fetched representation") do
  event_content = artifact_events(@external_reference_id).sole.data.dig("artifact", "content")
  projected = artifact_content(@external_reference_id).dig("data", "content")
  assert_acceptance(!event_content.key?("base64"), "Reference event exposed Base64")
  assert_acceptance(!projected.key?("base64"), "Reference query exposed Base64")
  assert_acceptance_equal("text/uri-list", projected.fetch("media_type"), "Reference media type")
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

Given("a README, two linked documents, and another parent are captured and mapped") do
  definitions = {
    readme: {
      command_id: "cmd-cuc-linked-readme",
      title: "Project README",
      locator: "README.md",
      text: "[Guide](docs/guide.md#install) [API](guide/../docs/api.md#v1)\n"
    },
    guide: {
      command_id: "cmd-cuc-linked-guide",
      title: "Guide",
      locator: "docs/guide.md",
      text: "Guide body\n"
    },
    api: {
      command_id: "cmd-cuc-linked-api",
      title: "API",
      locator: "docs/api.md",
      text: "API body\n"
    },
    index: {
      command_id: "cmd-cuc-linked-index",
      title: "Documentation index",
      locator: "docs/index.md",
      text: "Index body\n"
    }
  }
  @linked_artifacts = definitions.to_h do |name, definition|
    outcome = capture_artifact_task(
      command_id: definition.fetch(:command_id),
      title: definition.fetch(:title),
      kind: "documentation",
      labels: %w[linked navigation],
      locator: definition.fetch(:locator),
      source_kind: "local_file",
      content: {
        encoding: "utf-8",
        media_type: "text/markdown",
        text: definition.fetch(:text)
      }
    )
    [
      name,
      {
        artifact_id: outcome.dig("data", "artifact_id"),
        text: definition.fetch(:text)
      }
    ]
  end
end

Given("the caller declares README links with parent-segment and fragment evidence") do
  readme = @linked_artifacts.fetch(:readme).fetch(:artifact_id)
  guide = @linked_artifacts.fetch(:guide).fetch(:artifact_id)
  api = @linked_artifacts.fetch(:api).fetch(:artifact_id)
  @linked_relations = {}
  @linked_relations[:guide] = declare_artifact_relation_task(
    command_id: "cmd-cuc-linked-readme-guide",
    source_artifact_id: readme,
    relation: "references",
    target: { kind: "artifact", id: guide },
    attributes: {
      path: "docs/guide.md",
      fragment: "install",
      normalized_locator: "docs/guide.md"
    }
  )
  @linked_relations[:api] = declare_artifact_relation_task(
    command_id: "cmd-cuc-linked-readme-api",
    source_artifact_id: readme,
    relation: "references",
    target: { kind: "artifact", id: api },
    attributes: {
      path: "guide/../docs/api.md",
      fragment: "v1",
      normalized_locator: "docs/api.md"
    }
  )
end

Given("the other parent contains the shared API document") do
  @linked_relations[:index] = declare_artifact_relation_task(
    command_id: "cmd-cuc-linked-index-api",
    source_artifact_id: @linked_artifacts.fetch(:index).fetch(:artifact_id),
    relation: "contains",
    target: {
      kind: "artifact",
      id: @linked_artifacts.fetch(:api).fetch(:artifact_id)
    }
  )
end

When("the linked Artifact facts reach the read side") do
  @linked_artifacts.each_value { project_artifact(_1.fetch(:artifact_id)) }
  expected_relation_ids = @linked_relations.values.map do |outcome|
    outcome.dig(:result, "data", "relation_id")
  end.sort
  await_read_model("Every linked Artifact edge to become available") do
    readme = artifact_relation_page(
      @linked_artifacts.fetch(:readme).fetch(:artifact_id),
      direction: "outgoing"
    )
    api = artifact_relation_page(
      @linked_artifacts.fetch(:api).fetch(:artifact_id),
      direction: "incoming"
    )
    observed_relation_ids = (readme.fetch("items") + api.fetch("items"))
      .map { _1.fetch("relation_id") }
      .uniq
      .sort
    [ observed_relation_ids == expected_relation_ids, { readme:, api: } ]
  end
end

When("the clean agent walks outgoing relationships from the README") do
  @readme_outgoing = artifact_relation_page(
    @linked_artifacts.fetch(:readme).fetch(:artifact_id),
    direction: "outgoing"
  )
end

Then("it discovers both exact child Artifacts and fetches their passive content") do
  expected = %i[guide api].map { @linked_artifacts.fetch(_1).fetch(:artifact_id) }.sort
  items = @readme_outgoing.fetch("items")
  assert_acceptance_equal(expected, items.map { _1.fetch("peer_id") }.sort, "README children")
  assert_acceptance(items.all? { _1.fetch("peer_artifact") }, "Available peer summaries")

  actual_content = items.to_h do |item|
    artifact_id = item.fetch("peer_id")
    payload = artifact_content(artifact_id)
    assert_acceptance(payload.fetch("warnings").sole.include?("passive data"), "Passive child content")
    [ artifact_id, payload.dig("data", "content", "text") ]
  end
  expected_content = %i[guide api].to_h do |name|
    artifact = @linked_artifacts.fetch(name)
    [ artifact.fetch(:artifact_id), artifact.fetch(:text) ]
  end
  assert_acceptance_equal(expected_content, actual_content, "Child content by exact ID")
end

When("the clean agent walks incoming relationships from the shared API document") do
  @api_incoming = artifact_relation_page(
    @linked_artifacts.fetch(:api).fetch(:artifact_id),
    direction: "incoming"
  )
end

Then("it sees both exact parents with mixed relationship kinds and peer summaries") do
  expected_parents = %i[readme index].map { @linked_artifacts.fetch(_1).fetch(:artifact_id) }.sort
  items = @api_incoming.fetch("items")
  assert_acceptance_equal(expected_parents, items.map { _1.fetch("peer_id") }.sort, "API parents")
  assert_acceptance_equal(%w[contains references], items.map { _1.fetch("relation") }.sort, "Relation kinds")
  assert_acceptance(
    items.all? { _1.dig("peer_artifact", "artifact_id") == _1.fetch("peer_id") },
    "Incoming peer summaries"
  )
end

Then("the README edge preserves its literal parent-segment, fragment, and normalized locator") do
  readme = @linked_artifacts.fetch(:readme).fetch(:artifact_id)
  edge = @api_incoming.fetch("items").find { _1.fetch("source_artifact_id") == readme }
  assert_acceptance(edge, "README to API edge")
  assert_acceptance_equal(
    {
      "path" => "guide/../docs/api.md",
      "fragment" => "v1",
      "normalized_locator" => "docs/api.md"
    },
    edge.fetch("attributes"),
    "Literal and normalized link evidence"
  )
end

Given("two immutable revisions at one exact locator are captured but not projected") do
  @locator_artifacts = %w[commit-a commit-b].to_h do |revision|
    outcome = capture_artifact_task(
      command_id: "cmd-cuc-locator-#{revision}",
      title: "Version #{revision}",
      kind: "documentation",
      labels: %w[linked versioned],
      locator: "docs/versioned.md",
      source_kind: "local_file",
      revision:,
      content: {
        encoding: "utf-8",
        media_type: "text/markdown",
        text: "#{revision}\n"
      }
    )
    [ revision, outcome.dig("data", "artifact_id") ]
  end
end

When("the clean agent resolves that locator before projection") do
  @locator_before_projection = artifact_locator_page("docs/versioned.md")
end

Then("the locator is absent with a bounded projection-lag retry action") do
  page = @locator_before_projection.dig("data", "page")
  assert_acceptance_equal("absent", page.fetch("resolution"), "Unprojected locator resolution")
  assert_acceptance_equal([], page.fetch("items"), "Unprojected locator items")
  action = @locator_before_projection.fetch("next_actions").sole
  assert_acceptance_equal("development_artifact_locator_resolve", action.fetch("tool"), "Lag retry tool")
  assert_acceptance(
    action.dig("arguments", "cursor", "after_observed_sequence") >= 0,
    "Bounded lag retry cursor"
  )
end

When("both locator revisions reach the read side") do
  @locator_artifacts.each_value { project_artifact(_1) }
  @ambiguous_locator_pages = []
  response = artifact_locator_page("docs/versioned.md", limit: 1)
  loop do
    @ambiguous_locator_pages << response
    break unless response.dig("data", "page", "has_more")

    continuation = response.fetch("next_actions").find do |action|
      !action.fetch("arguments").key?("source_revision")
    end
    assert_acceptance(continuation, "Locator page omitted its continuation action")
    response = follow_artifact_action(continuation)
  end
end

Then("the locator is ambiguous and offers both exact revisions without choosing latest") do
  pages = @ambiguous_locator_pages.map { _1.dig("data", "page") }
  assert_acceptance(pages.all? { _1.fetch("resolution") == "ambiguous" }, "Version ambiguity")
  assert_acceptance_equal(
    @locator_artifacts.values.sort,
    pages.flat_map { _1.fetch("items") }.map { _1.fetch("artifact_id") }.sort,
    "Ambiguous immutable Artifacts"
  )
  @locator_revision_actions = @ambiguous_locator_pages.flat_map do |response|
    response.fetch("next_actions").select do |action|
      action.fetch("arguments").key?("source_revision")
    end
  end
  revisions = @locator_revision_actions.map do |action|
    action.dig("arguments", "source_revision")
  end
  assert_acceptance_equal(%w[commit-a commit-b], revisions.sort, "Exact revision actions")
  assert_acceptance(
    @ambiguous_locator_pages.flat_map { _1.fetch("next_actions") }.none? do |action|
      action.fetch("tool") == "development_artifact_content_get"
    end,
    "No implicit content selection"
  )
end

When("the clean agent follows one exact revision action") do
  action = @locator_revision_actions.find do |candidate|
    candidate.dig("arguments", "source_revision") == "commit-b"
  end
  assert_acceptance(action, "Exact commit-b locator action")
  @exact_locator = follow_artifact_action(action)
end

Then("exactly that immutable Artifact and its content action are returned") do
  page = @exact_locator.dig("data", "page")
  assert_acceptance_equal("unique", page.fetch("resolution"), "Exact revision resolution")
  assert_acceptance_equal(
    @locator_artifacts.fetch("commit-b"),
    page.fetch("items").sole.fetch("artifact_id"),
    "Exact revision Artifact"
  )
  action = @exact_locator.fetch("next_actions").sole
  assert_acceptance_equal("development_artifact_content_get", action.fetch("tool"), "Content action")
end

Then("an unknown exact locator remains honestly absent") do
  missing = artifact_locator_page("docs/not-captured.md")
  assert_acceptance_equal("absent", missing.dig("data", "page", "resolution"), "Missing locator")
end

Given("a captured parent and child are available for relationship replay") do
  @replay_parent = capture_artifact_task(
    command_id: "cmd-cuc-relation-replay-parent",
    title: "Replay parent",
    kind: "documentation",
    labels: %w[linked replay],
    locator: "replay/README.md",
    source_kind: "local_file",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "Parent\n" }
  ).dig("data", "artifact_id")
  @replay_child = capture_artifact_task(
    command_id: "cmd-cuc-relation-replay-child",
    title: "Replay child",
    kind: "documentation",
    labels: %w[linked replay],
    locator: "replay/child.md",
    source_kind: "local_file",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "Child\n" }
  ).dig("data", "artifact_id")
  project_artifact(@replay_parent)
  project_artifact(@replay_child)
end

When("the same relationship command is executed through two Tasks") do
  arguments = {
    command_id: "cmd-cuc-relation-exact-replay",
    actor: { kind: "agent", id: "artifact-agent" },
    source_artifact_id: @replay_parent,
    relation: "references",
    target: { kind: "artifact", id: @replay_child },
    attributes: { path: "child.md", normalized_locator: "replay/child.md" }
  }
  @relation_replay_task_ids = 2.times.map do
    submit_and_execute("development_artifact_relation_declare", **arguments)
  end
  @relation_replay_results = @relation_replay_task_ids.map do |task_id|
    task_request("tasks/get", task_id).dig("result", "result", "structuredContent")
  end
end

When("its relation fact reaches the read side after a subscription restart") do
  event = artifact_events(@replay_parent).find { _1.type == "DevelopmentArtifactRelationDeclared" }
  assert_acceptance(event, "Replay relation fact")
  restart_read_model_subscriptions
  project_artifact_event(event)
end

Then("both Tasks expose one logical relation result") do
  assert_acceptance_equal(
    1,
    @relation_replay_results.map { _1.fetch("data") }.uniq.length,
    "Replay Task relation result"
  )
end

Then("one relation fact, command receipt, and projected edge exist") do
  relations = artifact_events(@replay_parent).count do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
  end
  assert_acceptance_equal(1, relations, "Durable replay relation facts")
  assert_acceptance_equal(
    1,
    command_events("cmd-cuc-relation-exact-replay").length,
    "Replay command receipts"
  )
  page = artifact_relation_page(@replay_parent, direction: "outgoing")
  assert_acceptance_equal(1, page.fetch("items").length, "Projected replay relationships")
end

Given("an earlier-captured parent has two committed relationships but only the later declaration is projected") do
  definitions = {
    parent: [ "cmd-cuc-late-parent", "late/README.md", "Parent\n" ],
    older: [ "cmd-cuc-late-older", "late/older.md", "Older\n" ],
    later: [ "cmd-cuc-late-later", "late/later.md", "Later\n" ]
  }
  @late_artifacts = definitions.to_h do |name, (command_id, locator, text)|
    outcome = capture_artifact_task(
      command_id:,
      title: name.to_s.capitalize,
      kind: "documentation",
      labels: %w[linked late],
      locator:,
      source_kind: "local_file",
      content: { encoding: "utf-8", media_type: "text/markdown", text: }
    )
    [ name, outcome.dig("data", "artifact_id") ]
  end
  @late_artifacts.each_value { project_artifact(_1) }

  older = declare_artifact_relation_task(
    command_id: "cmd-cuc-late-edge-older",
    source_artifact_id: @late_artifacts.fetch(:parent),
    relation: "references",
    target: { kind: "artifact", id: @late_artifacts.fetch(:older) },
    attributes: { path: "older.md", normalized_locator: "late/older.md" }
  )
  later = declare_artifact_relation_task(
    command_id: "cmd-cuc-late-edge-later",
    source_artifact_id: @late_artifacts.fetch(:parent),
    relation: "contains",
    target: { kind: "artifact", id: @late_artifacts.fetch(:later) }
  )
  @late_relation_ids = {
    older: older.dig(:result, "data", "relation_id"),
    later: later.dig(:result, "data", "relation_id")
  }
  declarations = artifact_events(@late_artifacts.fetch(:parent)).select do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
  end
  @late_declarations = declarations.index_by do |event|
    event.data.dig("artifact_relation", "relation_id")
  end
  project_artifact_event(@late_declarations.fetch(@late_relation_ids.fetch(:later)))
end

When("the clean agent reads one outgoing relationship page") do
  @late_first_page = artifact_relation_page(
    @late_artifacts.fetch(:parent),
    direction: "outgoing",
    limit: 1
  )
end

Then("the available page contains the later declaration and a completed observation window") do
  assert_acceptance_equal(
    @late_relation_ids.fetch(:later),
    @late_first_page.fetch("items").sole.fetch("relation_id"),
    "Initially projected relation"
  )
  assert_acceptance_equal(false, @late_first_page.fetch("has_more"), "Initial observation window")
  assert_acceptance(
    @late_first_page.dig("continuation_cursor", "after_observed_sequence").positive?,
    "Observation continuation"
  )
  assert_acceptance_equal(
    nil,
    @late_first_page.dig("continuation_cursor", "through_observed_sequence"),
    "Completed fixed window"
  )
end

When("the older declaration reaches the read side after that cursor") do
  project_artifact_event(@late_declarations.fetch(@late_relation_ids.fetch(:older)))
end

When("the clean agent resumes from the returned relationship cursor") do
  @late_resumed_page = artifact_relation_page(
    @late_artifacts.fetch(:parent),
    direction: "outgoing",
    limit: 1,
    cursor: @late_first_page.fetch("continuation_cursor")
  )
end

Then("the older declaration is returned despite its earlier event position") do
  resumed = @late_resumed_page.fetch("items").sole
  initial = @late_first_page.fetch("items").sole
  assert_acceptance_equal(
    @late_relation_ids.fetch(:older),
    resumed.fetch("relation_id"),
    "Late older relation"
  )
  assert_acceptance(
    resumed.dig("declared", "global_position") < initial.dig("declared", "global_position"),
    "Late relation event position"
  )
end

Given("a projected Artifact relationship and an unprojected replacement are available") do
  definitions = {
    parent: [ "cmd-cuc-supersession-parent", "supersession/README.md" ],
    original: [ "cmd-cuc-supersession-original", "supersession/original.md" ],
    replacement: [ "cmd-cuc-supersession-replacement", "supersession/replacement.md" ]
  }
  @supersession_artifacts = definitions.to_h do |name, (command_id, locator)|
    outcome = capture_artifact_task(
      command_id:,
      title: name.to_s.capitalize,
      kind: "documentation",
      labels: %w[linked supersession],
      locator:,
      source_kind: "local_file",
      content: { encoding: "utf-8", media_type: "text/markdown", text: "#{name}\n" }
    )
    [ name, outcome.dig("data", "artifact_id") ]
  end
  @supersession_artifacts.each_value { project_artifact(_1) }

  original = declare_artifact_relation_task(
    command_id: "cmd-cuc-supersession-edge-original",
    source_artifact_id: @supersession_artifacts.fetch(:parent),
    relation: "references",
    target: { kind: "artifact", id: @supersession_artifacts.fetch(:original) },
    attributes: { path: "original.md" }
  )
  @supersession_relation_ids = { original: original.dig(:result, "data", "relation_id") }
  original_event = artifact_events(@supersession_artifacts.fetch(:parent)).find do |event|
    event.data.dig("artifact_relation", "relation_id") == @supersession_relation_ids.fetch(:original)
  end
  project_artifact_event(original_event)

  replacement = declare_artifact_relation_task(
    command_id: "cmd-cuc-supersession-edge-replacement",
    source_artifact_id: @supersession_artifacts.fetch(:parent),
    relation: "references",
    target: { kind: "artifact", id: @supersession_artifacts.fetch(:replacement) },
    attributes: { path: "replacement.md" },
    supersedes: {
      relation_id: @supersession_relation_ids.fetch(:original),
      reason: "README now references the replacement."
    }
  )
  @supersession_relation_ids[:replacement] = replacement.dig(:result, "data", "relation_id")
  events = artifact_events(@supersession_artifacts.fetch(:parent))
  @supersession_event = events.find { _1.type == "DevelopmentArtifactRelationSuperseded" }
  @replacement_declaration = events.find do |event|
    event.data.dig("artifact_relation", "relation_id") == @supersession_relation_ids.fetch(:replacement)
  end
end

When("the clean agent completes the initial relationship observation window") do
  @supersession_initial_page = artifact_relation_page(
    @supersession_artifacts.fetch(:parent),
    direction: "outgoing",
    limit: 10,
    include_superseded: true
  )
  assert_acceptance_equal(false, @supersession_initial_page.fetch("has_more"), "Initial relation window")
end

When("the supersession reaches the read side before its replacement declaration") do
  project_artifact_event(@supersession_event)
end

Then("resuming the completed cursor exposes the original relationship as superseded") do
  @supersession_resumed_page = artifact_relation_page(
    @supersession_artifacts.fetch(:parent),
    direction: "outgoing",
    limit: 10,
    cursor: @supersession_initial_page.fetch("continuation_cursor"),
    include_superseded: true
  )
  item = @supersession_resumed_page.fetch("items").sole
  assert_acceptance_equal(@supersession_relation_ids.fetch(:original), item.fetch("relation_id"), "Updated edge")
  assert_acceptance_equal("superseded", item.fetch("status"), "Updated edge status")
end

When("the supersession is replayed and its older replacement declaration arrives") do
  project_artifact_event(@supersession_event)
  project_artifact_event(@replacement_declaration)
end

Then("the next cursor exposes the active replacement once without regressing the original edge") do
  page = artifact_relation_page(
    @supersession_artifacts.fetch(:parent),
    direction: "outgoing",
    limit: 10,
    cursor: @supersession_resumed_page.fetch("continuation_cursor"),
    include_superseded: true
  )
  assert_acceptance_equal(
    [ @supersession_relation_ids.fetch(:replacement) ],
    page.fetch("items").map { _1.fetch("relation_id") },
    "Replacement observation"
  )
  assert_acceptance_equal("active", page.fetch("items").sole.fetch("status"), "Replacement status")
end
