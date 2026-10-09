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
        development_artifact_capture_batch development_artifact_update
        development_artifact_relation_declare
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
  artifact_update = @migration_tools.find { _1.fetch("name") == "development_artifact_update" }
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
  update_schema = artifact_update.fetch("inputSchema")
  assert_acceptance(
    Regexp.new(update_schema.dig("properties", "artifact_id", "pattern")).match?(SecureRandom.uuid_v7),
    "Stable Artifact UUIDv7 identity"
  )
  assert_acceptance_equal(
    %w[content kind labels scope source title],
    update_schema.dig("properties", "changes", "properties").keys.sort,
    "Mutable Artifact properties"
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

Then("both Artifact Tasks complete with different stable UUIDv7 IDs") do
  assert_acceptance(@artifact_outcomes.all? { _1.fetch("status") == "ok" }, "Capture outcomes")
  @artifact_ids = @artifact_outcomes.map { _1.dig("data", "artifact_id") }
  assert_acceptance_equal(2, @artifact_ids.uniq.length, "Artifact identities")
  assert_acceptance(
    @artifact_ids.all? { Coordinator::Shared::Types::UUID_V7_PATTERN.match?(_1) },
    "Artifact identities must be UUIDv7"
  )
end

When("the Development Artifact facts reach the read side") do
  @artifact_ids.each { project_artifact(_1) }
end

Then("listing the shared evidence labels returns both Artifacts") do
  page = await_read_model("Both exactly labelled Artifacts to become discoverable") do
    observed = call_tool(
      "development_artifact_list",
      { scope: "project:acceptance", labels: %w[evidence imported], limit: 20 }
    ).dig("result", "structuredContent", "data", "page")
    ids = observed.fetch("items").map { _1.fetch("artifact_id") }.sort
    [ ids == @artifact_ids.sort, observed ]
  end
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
  event = artifact_events(@external_reference_id).find do |candidate|
    candidate.type == "DevelopmentArtifactContentChanged"
  end
  assert_acceptance(event, "External-reference content fact")
  projected = artifact_content(@external_reference_id).dig("data", "content")
  expected = "#{@external_reference_url}\n"
  assert_acceptance_equal(
    { "artifact_id" => @external_reference_id, "content" => expected },
    event.data,
    "Persisted reference fact"
  )
  assert_acceptance_equal(expected, projected.fetch("text"), "Projected reference")
end

Then("the external-reference content contains no binary or fetched representation") do
  event = artifact_events(@external_reference_id).find do |candidate|
    candidate.type == "DevelopmentArtifactContentChanged"
  end
  projected = artifact_content(@external_reference_id).dig("data", "content")
  assert_acceptance_equal("utf-8", event.metadata.fetch("encoding"), "Reference event encoding")
  assert_acceptance(!event.data.key?("base64"), "Reference event exposed Base64")
  assert_acceptance(!projected.key?("base64"), "Reference query exposed Base64")
  assert_acceptance_equal("text/uri-list", projected.fetch("media_type"), "Reference media type")
end

Given("the agent has captured and projected a binary profile") do
  @profile_contents = [ "\x00\x01".b, "\x00\x02".b ]
  capture = capture_artifact_task(
    command_id: "cmd-cuc-profile-capture",
    title: "Runtime profile",
    kind: "performance_profile",
    labels: %w[profile binary],
    locator: "tmp/profile.dump",
    source_kind: "local_file",
    revision: "profile-a",
    content: {
      encoding: "binary",
      media_type: "application/octet-stream",
      base64: [ @profile_contents.first ].pack("m0")
    }
  )
  assert_acceptance_equal("ok", capture.fetch("status"), "Binary capture Task")
  @profile_id = capture.dig("data", "artifact_id")
  projected = project_artifact(@profile_id)
  @profile_initial_revision = projected.dig("data", "artifact", "artifact", "stream_revision")
end

When("the agent updates its binary content and provenance through MCP") do
  @profile_update = update_artifact_task(
    command_id: "cmd-cuc-profile-update",
    artifact_id: @profile_id,
    expected_revision: @profile_initial_revision,
    changes: {
      content: {
        encoding: "binary",
        media_type: "application/octet-stream",
        base64: [ @profile_contents.last ].pack("m0")
      },
      source: {
        kind: "local_file",
        locator: "tmp/profile.dump",
        revision: "profile-b",
        observed_at: "2026-08-25T16:30:00.000000Z",
        collector: "cucumber/v2"
      }
    }
  )
end

Then("the update Task keeps its stable UUIDv7 Artifact ID") do
  assert_acceptance_equal("ok", @profile_update.fetch("status"), "Binary update Task")
  assert_acceptance_equal(@profile_id, @profile_update.dig("data", "artifact_id"), "Stable Artifact identity")
  assert_acceptance(
    Coordinator::Shared::Types::UUID_V7_PATTERN.match?(@profile_id),
    "Binary profile identity must be UUIDv7"
  )
end

Then("the Artifact stream records only content and source change facts") do
  facts = artifact_events(@profile_id).select do |event|
    event.stream_revision > @profile_initial_revision
  end
  assert_acceptance_equal(
    %w[DevelopmentArtifactContentChanged DevelopmentArtifactSourceChanged],
    facts.map(&:type),
    "Updated property facts"
  )
  assert_acceptance_equal(
    { "artifact_id" => @profile_id, "content" => [ @profile_contents.last ].pack("m0") },
    facts.first.data,
    "Binary content fact"
  )
  assert_acceptance(
    facts.none? { |event| (event.data.keys & %w[scope title kind labels]).any? },
    "Unchanged properties were copied into update facts"
  )
end

When("the changed binary Artifact facts reach the read side") do
  expected_revision = @profile_update.dig("data", "resulting_stream_revision")
  @profile_content = await_read_model("Changed binary profile to become available") do
    view = artifact_view(@profile_id).dig("data", "artifact", "artifact")
    payload = artifact_content(@profile_id)
    matches = view&.fetch("stream_revision", -1) == expected_revision &&
      payload.dig("data", "content", "base64") == [ @profile_contents.last ].pack("m0")
    [ matches, payload ]
  end
end

Then("its current content is the changed Base64 payload and is never executed") do
  assert_acceptance_equal(
    [ @profile_contents.last ].pack("m0"),
    @profile_content.dig("data", "content", "base64"),
    "Binary profile content"
  )
  assert_acceptance(@profile_content.fetch("warnings").sole.include?("passive data"), "Passive warning")
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

Given("two source revisions at one exact locator are captured but not projected") do
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
        text: "stable content\n"
      }
    )
    [
      revision,
      {
        artifact_id: outcome.dig("data", "artifact_id"),
        observation_id: outcome.dig("data", "observation_id")
      }
    ]
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
  @locator_artifacts.each_value do |artifact|
    project_artifact(
      artifact.fetch(:artifact_id),
      observation_id: artifact.fetch(:observation_id)
    )
  end
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
    @locator_artifacts.values.map { _1.fetch(:artifact_id) }.sort,
    pages.flat_map { _1.fetch("items") }.map { _1.fetch("artifact_id") }.sort,
    "Ambiguous revision Artifacts"
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

Then("exactly that revision's Artifact and its content action are returned") do
  page = @exact_locator.dig("data", "page")
  assert_acceptance_equal("unique", page.fetch("resolution"), "Exact revision resolution")
  assert_acceptance_equal(
    @locator_artifacts.fetch("commit-b").fetch(:artifact_id),
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

When("the same relationship command is submitted twice") do
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
  relation_id = @relation_replay_results.first.dig("data", "relation_id")
  event = artifact_relation_events(relation_id).find { _1.type == "DevelopmentArtifactRelationDeclared" }
  assert_acceptance(event, "Replay relation fact")
  restart_read_model_subscriptions
  project_artifact_event(event)
end

Then("both responses expose the original Task and one logical relation result") do
  assert_acceptance_equal(1, @relation_replay_task_ids.uniq.length, "Replay Task identity")
  assert_acceptance_equal(
    1,
    @relation_replay_results.map { _1.fetch("data") }.uniq.length,
    "Replay Task relation result"
  )
end

Then("one relation fact, command lifecycle, and projected edge exist") do
  relation_id = @relation_replay_results.first.dig("data", "relation_id")
  relations = artifact_relation_events(relation_id).count do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
  end
  assert_acceptance_equal(1, relations, "Durable replay relation facts")
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events("cmd-cuc-relation-exact-replay").map(&:type),
    "Replay command lifecycle"
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
  @late_declarations = @late_relation_ids.values.to_h do |relation_id|
    event = artifact_relation_events(relation_id).find do |candidate|
      candidate.type == "DevelopmentArtifactRelationDeclared"
    end
    [ relation_id, event ]
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
  original_event = artifact_relation_events(@supersession_relation_ids.fetch(:original)).find do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
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
  original_events = artifact_relation_events(@supersession_relation_ids.fetch(:original))
  @supersession_event = original_events.find { _1.type == "DevelopmentArtifactRelationSuperseded" }
  @replacement_declaration = artifact_relation_events(
    @supersession_relation_ids.fetch(:replacement)
  ).find do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
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

Then("Artifact evidence uses current facts and native event timestamps") do
  @artifact_outcomes.each do |outcome|
    artifact_id = outcome.dig("data", "artifact_id")
    observation_id = outcome.dig("data", "observation_id")
    facts = artifact_events(artifact_id)
    observation_facts = artifact_observation_events(observation_id)
    created = facts.find { _1.type == "DevelopmentArtifactCreated" }
    recorded = observation_facts.find { _1.type == "DevelopmentArtifactObservationRecorded" }
    view = artifact_view(artifact_id, observation_id:).dig("data", "artifact", "artifact")

    assert_acceptance_equal([ "artifact_id" ], created.data.keys, "Minimal creation fact")
    assert_acceptance_equal([ "observation_id" ], recorded.data.keys, "Minimal observation fact")
    assert_acceptance_equal(created.id, view.dig("captured", "event", "event_id"), "Creation source identity")
    assert_acceptance_equal(recorded.id, view.dig("observed", "event", "event_id"), "Observation source identity")
    assert_acceptance_equal(created.created_at.utc.iso8601(6), view.dig("captured", "occurred_at"), "Native creation time")
    assert_acceptance_equal(recorded.created_at.utc.iso8601(6), view.dig("observed", "occurred_at"), "Native observation time")
    (facts + observation_facts).each do |event|
      assert_acceptance_equal(1, event.metadata.fetch("schema_version"), "Current granular schema")
      assert_acceptance(
        Coordinator::Shared::Types::UUID_V7_PATTERN.match?(event.stream.stream_id),
        "UUIDv7 Artifact stream identity"
      )
      assert_acceptance((event.data.keys & %w[captured_at recorded_at corrected_at completed_at]).empty?, "Duplicated occurrence time")
    end
    content = facts.find { _1.type == "DevelopmentArtifactContentChanged" }
    assert_acceptance_equal(%w[artifact_id content], content.data.keys.sort, "Cohesive content data")
    assert_acceptance(
      %w[encoding media_type byte_size content_sha256].all? { content.metadata.key?(_1) },
      "Typed server-computed content descriptors"
    )
  end
end
