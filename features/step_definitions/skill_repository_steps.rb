# frozen_string_literal: true

When("the agent publishes Skill {string} in scopes {string} and {string}") do |name, first_scope, second_scope|
  @scoped_skill_publications = [ first_scope, second_scope ].map do |scope|
    publish_skill_task(
      name:,
      scope:,
      command_id: "cmd-cuc-skill-#{scope}",
      expected_revision: 0,
      instructions: "Use the #{scope} review policy.",
      assets: []
    )
  end
end

Then("both scoped Skill Tasks complete at revision 1 with different Skill IDs") do
  outcomes = @scoped_skill_publications.map { _1.fetch(:outcome) }
  assert_acceptance(outcomes.all? { _1.fetch("status") == "ok" }, "Both publications must succeed")
  revisions = outcomes.map { _1.dig("data", "revision") }
  skill_ids = outcomes.map { _1.dig("data", "skill_id") }
  assert_acceptance_equal([ 1, 1 ], revisions, "Scoped revisions")
  assert_acceptance_equal(2, skill_ids.uniq.length, "Scoped Skill identities")
end

When("both scoped Skill facts reach the read side") do
  @scoped_skill_publications.each do |publication|
    outcome = publication.fetch(:outcome)
    skill_events(name: outcome.dig("data", "name"), scope: outcome.dig("data", "scope")).each do |event|
      await_skill_revision(event)
    end
  end
end

Then("listing Skill {string} exposes both exact scopes") do |name|
  page = call_tool("skill_list", { name:, limit: 20 })
    .dig("result", "structuredContent", "data", "page")
  assert_acceptance_equal(%w[home work], page.fetch("items").map { _1.fetch("scope") }.sort, "Exact scopes")
end

Then("each scoped Skill returns its own instructions") do
  home = skill_view(name: "review", scope: "home").dig("data", "skill")
  work = skill_view(name: "review", scope: "work").dig("data", "skill")
  assert_acceptance_equal("Use the home review policy.", home.fetch("instructions"), "Home instructions")
  assert_acceptance_equal("Use the work review policy.", work.fetch("instructions"), "Work instructions")
end

Given("Skill {string} in scope {string} has projected revision 1") do |name, scope|
  @lagging_skill_name = name
  @lagging_skill_scope = scope
  @first_skill_publication = publish_skill_task(
    name:,
    scope:,
    command_id: "cmd-cuc-skill-lag-1",
    expected_revision: 0,
    instructions: "Revision one instructions.",
    assets: []
  )
  await_skill_revision(skill_events(name:, scope:).sole)
end

When("the agent publishes revision 2 without projecting it") do
  @second_skill_publication = publish_skill_task(
    name: @lagging_skill_name,
    scope: @lagging_skill_scope,
    command_id: "cmd-cuc-skill-lag-2",
    expected_revision: 1,
    instructions: "Revision two instructions.",
    assets: []
  )
end

Then("Skill {string} remains available at projected revision 1") do |name|
  payload = skill_view(name:, scope: @lagging_skill_scope)
  assert_acceptance_equal("ok", payload.fetch("status"), "Lagging Skill availability")
  assert_acceptance_equal(1, payload.dig("data", "skill", "revision"), "Lagging Skill revision")
end

When("the agent attempts another publication from stale revision 1") do
  @stale_skill_publication = publish_skill_task(
    name: @lagging_skill_name,
    scope: @lagging_skill_scope,
    command_id: "cmd-cuc-skill-lag-stale",
    expected_revision: 1,
    instructions: "A stale competing revision.",
    assets: []
  )
end

Then("the stale Skill Task completes with revision conflict and a rejected command lifecycle") do
  state = @stale_skill_publication.fetch(:state)
  outcome = @stale_skill_publication.fetch(:outcome)
  assert_acceptance_equal("completed", state.dig("result", "status"), "Stale Task status")
  assert_acceptance_equal("conflict", outcome.fetch("status"), "Stale publication status")
  assert_acceptance_equal("skill_revision_conflict", outcome.dig("data", "code"), "Stale denial code")
  assert_acceptance(
    outcome.fetch("summary").include?("retry"),
    "Revision conflict must explain that a fresh retry can succeed"
  )
  assert_acceptance_equal(
    { "tool" => "skill_get", "arguments" => { "name" => @lagging_skill_name, "scope" => @lagging_skill_scope } },
    outcome.fetch("next_actions").sole,
    "Revision conflict recovery action"
  )
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@stale_skill_publication.fetch(:command_id)).map(&:type),
    "Stale command facts"
  )
end

When("Skill revision 2 reaches the read side") do
  await_skill_revision(skill_events(name: @lagging_skill_name, scope: @lagging_skill_scope).last)
end

Then("Skill {string} is available at revision 2 without a freshness field") do |name|
  payload = skill_view(name:, scope: @lagging_skill_scope)
  assert_acceptance_equal(2, payload.dig("data", "skill", "revision"), "Projected Skill revision")
  assert_acceptance(
    (payload.keys & %w[fresh pending projection_status]).empty?,
    "Skill response must not expose a freshness gate"
  )
end

When("the agent publishes Skill {string} with script asset {string}") do |name, path|
  @asset_skill_name = name
  @asset_skill_scope = "project:alpha"
  @asset_path = path
  @asset_content = "#!/bin/sh\nbundle exec rspec\n"
  @asset_publication = publish_skill_task(
    name:,
    scope: @asset_skill_scope,
    command_id: "cmd-cuc-skill-asset",
    expected_revision: 0,
    instructions: "Run the supplied check only after inspecting it.",
    assets: [ script_asset(path, @asset_content) ]
  )
end

When("the Skill publication reaches the read side") do
  await_skill_revision(skill_events(name: @asset_skill_name, scope: @asset_skill_scope).sole)
end

Then("the exact script asset content and digest are available through MCP") do
  payload = skill_asset(name: @asset_skill_name, scope: @asset_skill_scope, path: @asset_path)
  asset = payload.dig("data", "asset")
  assert_acceptance_equal("ok", payload.fetch("status"), "Asset query status")
  assert_acceptance_equal("utf-8", asset.fetch("encoding"), "Asset encoding")
  assert_acceptance_equal(@asset_content, asset.fetch("text"), "Asset content")
  assert_acceptance(!asset.key?("base64"), "UTF-8 asset must not expose Base64")
  assert_acceptance(
    asset.fetch("content_sha256").match?(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN),
    "Asset digest must be a SHA-256 digest"
  )
end

Then("the Skill view exposes the asset manifest without embedding its content") do
  skill = skill_view(name: @asset_skill_name, scope: @asset_skill_scope).dig("data", "skill")
  manifest = skill.fetch("assets").sole
  assert_acceptance_equal(@asset_path, manifest.fetch("path"), "Manifest path")
  assert_acceptance(
    (manifest.keys & %w[text base64 content_base64]).empty?,
    "Skill manifest must not embed asset content"
  )
end

When("the agent publishes and replays Skill {string} with Unicode text and binary assets") do |name|
  @semantic_skill_name = name
  @semantic_skill_scope = "project:semantic-content"
  @semantic_text_path = "docs/unicode.txt"
  @semantic_text = "Hej, världen — λ\n"
  @semantic_binary_path = "fixtures/raw.bin"
  @semantic_binary = "\x00\xFF\x10".b
  assets = [
    {
      path: @semantic_text_path,
      executable: false,
      content: { encoding: "utf-8", media_type: "text/plain", text: @semantic_text }
    },
    {
      path: @semantic_binary_path,
      executable: false,
      content: {
        encoding: "binary",
        media_type: "application/octet-stream",
        base64: [ @semantic_binary ].pack("m0")
      }
    }
  ]
  @semantic_skill_publications = 2.times.map do
    publish_skill_task(
      name:,
      scope: @semantic_skill_scope,
      command_id: "cmd-cuc-skill-semantic-replay",
      expected_revision: 0,
      instructions: "Retrieve each passive asset in its declared representation.",
      assets:
    )
  end
end

When("the semantic Skill fact reaches the read side") do
  await_skill_revision(
    skill_events(name: @semantic_skill_name, scope: @semantic_skill_scope).sole
  )
end

Then("the Unicode asset is returned as exact text without Base64") do
  asset = skill_asset(
    name: @semantic_skill_name,
    scope: @semantic_skill_scope,
    path: @semantic_text_path
  ).dig("data", "asset")
  assert_acceptance_equal("utf-8", asset.fetch("encoding"), "Unicode asset encoding")
  assert_acceptance_equal(@semantic_text, asset.fetch("text"), "Unicode asset text")
  assert_acceptance(!asset.key?("base64"), "Unicode asset exposed Base64")
end

Then("the binary asset is returned as exact Base64 without text") do
  asset = skill_asset(
    name: @semantic_skill_name,
    scope: @semantic_skill_scope,
    path: @semantic_binary_path
  ).dig("data", "asset")
  assert_acceptance_equal("binary", asset.fetch("encoding"), "Binary asset encoding")
  assert_acceptance_equal([ @semantic_binary ].pack("m0"), asset.fetch("base64"), "Binary asset")
  assert_acceptance(!asset.key?("text"), "Binary asset exposed text")
end

Then("replay leaves one semantic Skill publication fact") do
  outcomes = @semantic_skill_publications.map { _1.fetch(:outcome).fetch("data") }
  assert_acceptance_equal(1, outcomes.uniq.length, "Replay outcomes")
  publication = skill_events(name: @semantic_skill_name, scope: @semantic_skill_scope).sole
  assert_acceptance_equal(3, publication.metadata.fetch("schema_version"), "Skill event schema")
  contents = skill_fact_events(name: @semantic_skill_name, scope: @semantic_skill_scope)
    .select { _1.type == "SkillAssetContentDefined" }
  assert_acceptance_equal(2, contents.length, "Granular content facts")
  text_fact = contents.find { _1.metadata.fetch("encoding") == "utf-8" }
  binary_fact = contents.find { _1.metadata.fetch("encoding") == "binary" }
  assert_acceptance(text_fact, "Text fact")
  assert_acceptance(binary_fact, "Binary fact")
  assert_acceptance_equal(@semantic_text, text_fact.data.fetch("content"), "Text content fact")
  assert_acceptance_equal([ @semantic_binary ].pack("m0"), binary_fact.data.fetch("content"), "Binary content fact")
end

When("the agent submits a Skill asset with an invalid mixed encoding representation") do
  @invalid_semantic_skill_command_id = "cmd-cuc-skill-invalid-semantic-content"
  @invalid_semantic_skill_response = call_tool(
    "skill_publish",
    {
      command_id: @invalid_semantic_skill_command_id,
      actor: { kind: "agent", id: "skill-agent" },
      name: "invalid-semantic-assets",
      scope: "project:semantic-content",
      expected_revision: 0,
      description: "Invalid content boundary",
      instructions: "This request must not be accepted.",
      assets: [
        {
          path: "mixed.txt",
          executable: false,
          content: {
            encoding: "utf-8",
            media_type: "text/plain",
            text: "text\n",
            base64: "dGV4dAo="
          }
        }
      ]
    }
  )
end

Then("the invalid Skill request allocates no Task or command fact") do
  assert_acceptance_equal(true, @invalid_semantic_skill_response.dig("result", "isError"), "Schema error")
  assert_acceptance(
    @invalid_semantic_skill_response.dig("result", "content").sole.fetch("text").include?("Invalid arguments"),
    "Invalid content explanation"
  )
  assert_acceptance_equal([], task_events_for_command(@invalid_semantic_skill_command_id), "Task facts")
  assert_acceptance_equal([], command_events(@invalid_semantic_skill_command_id), "Command facts")
end

Given("Skill {string} in scope {string} has projected revisions 1 and 2 with different assets") do |name, scope|
  @historical_skill_name = name
  @historical_skill_scope = scope
  @historical_asset_path = "references/policy.txt"
  @historical_asset_content = "revision one policy\n"

  publish_skill_task(
    name:,
    scope:,
    command_id: "cmd-cuc-skill-history-1",
    expected_revision: 0,
    instructions: "Historical revision one.",
    assets: [ script_asset(@historical_asset_path, @historical_asset_content) ]
  )
  publish_skill_task(
    name:,
    scope:,
    command_id: "cmd-cuc-skill-history-2",
    expected_revision: 1,
    instructions: "Current revision two.",
    assets: [ script_asset("references/current.txt", "revision two policy\n") ]
  )
  await_skill_revision(skill_events(name:, scope:).last)
end

When("the agent retrieves the latest Skill {string} and follows its asset manifest") do |name|
  @historical_skill_view = skill_view(
    name:,
    scope: @historical_skill_scope
  )
  manifest = @historical_skill_view.dig("data", "skill", "assets").sole
  @historical_skill_asset = skill_asset(
    name:,
    scope: @historical_skill_scope,
    path: manifest.fetch("path")
  )
end

Then("the Skill metadata, manifest, and asset content all describe revision 2") do
  skill = @historical_skill_view.dig("data", "skill")
  manifest = skill.fetch("assets").sole
  asset = @historical_skill_asset.dig("data", "asset")

  assert_acceptance_equal("ok", @historical_skill_view.fetch("status"), "Historical Skill status")
  assert_acceptance_equal("ok", @historical_skill_asset.fetch("status"), "Historical asset status")
  assert_acceptance_equal(2, skill.fetch("revision"), "Latest Skill revision")
  assert_acceptance_equal(2, asset.fetch("revision"), "Latest asset revision")
  assert_acceptance_equal(manifest.fetch("content_sha256"), asset.fetch("content_sha256"), "Pinned digest")
  assert_acceptance_equal(
    "revision two policy\n",
    asset.fetch("text"),
    "Latest asset content"
  )
end

Then("retrieving Skill {string} without a revision returns revision 2") do |name|
  payload = skill_view(name:, scope: @historical_skill_scope || @replayed_skill_scope)
  assert_acceptance_equal("ok", payload.fetch("status"), "Current Skill status")
  assert_acceptance_equal(2, payload.dig("data", "skill", "revision"), "Current Skill revision")
end

Given("two independent MCP agents will publish Skill {string} in scope {string}") do |name, scope|
  @concurrent_skill_name = name
  @concurrent_skill_scope = scope
  @concurrent_skill_agents = [ "skill-agent-a", "skill-agent-b" ]
  prepare_mcp_clients(*@concurrent_skill_agents)
end

When("both agents submit expected revision 0 and reach the Skill decision boundary") do
  @concurrent_skill_publications = submit_tasks_in_distinct_execution_lanes(
    client_ids: @concurrent_skill_agents
  ) do |client_id, round|
    submit_skill_task(
      name: @concurrent_skill_name,
      scope: @concurrent_skill_scope,
      command_id: "cmd-cuc-skill-concurrent-#{client_id}-#{round}",
      expected_revision: 0,
      instructions: "Instructions proposed by #{client_id}.",
      assets: [],
      client_id:
    )
  end
  @concurrent_skill_commands = @concurrent_skill_publications.map { _1.fetch(:internal_command_id) }
  install_contention_barrier(
    operation: "skill_publish",
    command_ids: @concurrent_skill_commands
  )
  start_process_subscriptions
  await_contention_evidence
end

Then("both Skill publications have deterministic contention evidence") do
  assert_acceptance_equal(2, @contention_evidence.length, "Skill boundary arrivals")
  assert_acceptance_equal(
    @concurrent_skill_commands.sort,
    @contention_evidence.map { _1.fetch(:command_id) }.sort,
    "Skill boundary commands"
  )
  assert_acceptance_equal(2, @contention_evidence.map { _1.fetch(:thread_id) }.uniq.length, "Worker threads")
  assert_acceptance_equal([ 0, 1 ], @contention_evidence.map { _1.fetch(:worker_lane) }.sort, "Worker lanes")
end

When("the Skill decision boundary is released") do
  release_contention_barrier
  @concurrent_skill_publications.each do |publication|
    state = await_task_terminal(publication.fetch(:task_id), client_id: publication.fetch(:client_id))
    publication[:state] = state
    publication[:outcome] = state.dig("result", "result", "structuredContent")
  end
end

Then("one Skill Task publishes revision 1 and the other completes with revision conflict") do
  assert_acceptance(
    @concurrent_skill_publications.all? { _1.dig(:state, "result", "status") == "completed" },
    "Both Skill Tasks must complete"
  )
  statuses = @concurrent_skill_publications.map { _1.dig(:outcome, "status") }
  assert_acceptance_equal([ "conflict", "ok" ], statuses.sort, "Concurrent publication outcomes")
  @winning_skill_publication = @concurrent_skill_publications.find { _1.dig(:outcome, "status") == "ok" }
  conflict = @concurrent_skill_publications.find { _1.dig(:outcome, "status") == "conflict" }
  assert_acceptance_equal(1, @winning_skill_publication.dig(:outcome, "data", "revision"), "Winning revision")
  assert_acceptance_equal(
    "skill_revision_conflict",
    conflict.dig(:outcome, "data", "code"),
    "Losing conflict code"
  )
  assert_acceptance_equal(
    1,
    skill_events(name: @concurrent_skill_name, scope: @concurrent_skill_scope).length,
    "Published Skill facts"
  )
end

When("the winning Skill fact reaches the read side through live subscriptions") do
  event = skill_events(name: @concurrent_skill_name, scope: @concurrent_skill_scope).sole
  await_skill_revision(event)
end

Then("Skill {string} exposes exactly the winning revision 1 snapshot") do |name|
  skill = skill_view(name:, scope: @concurrent_skill_scope).dig("data", "skill")
  assert_acceptance_equal(1, skill.fetch("revision"), "Available Skill revision")
  assert_acceptance_equal(
    @winning_skill_publication.dig(:arguments, :instructions),
    skill.fetch("instructions"),
    "Winning Skill instructions"
  )
end

Given("Skill {string} in scope {string} has published revisions 1 and 2") do |name, scope|
  @replayed_skill_name = name
  @replayed_skill_scope = scope
  publish_skill_task(
    name:,
    scope:,
    command_id: "cmd-cuc-skill-replay-1",
    expected_revision: 0,
    instructions: "Replay revision one.",
    assets: [ script_asset("references/one.txt", "one\n") ]
  )
  publish_skill_task(
    name:,
    scope:,
    command_id: "cmd-cuc-skill-replay-2",
    expected_revision: 1,
    instructions: "Replay revision two.",
    assets: [ script_asset("references/two.txt", "two\n") ]
  )
end

When("both published Skill revisions reach the read side") do
  await_skill_revision(skill_events(name: @replayed_skill_name, scope: @replayed_skill_scope).last)
end

Then("the obsolete Skill revision is not retrievable") do
  obsolete = skill_view(name: @replayed_skill_name, scope: @replayed_skill_scope, revision: 1)
  assert_acceptance_equal("not_found", obsolete.fetch("status"), "Obsolete Skill revision")
end

Then("the Skill publication contains granular revision and asset facts") do
  facts = skill_fact_events(name: @asset_skill_name, scope: @asset_skill_scope)
  expected_types = %w[
    SkillRegistered
    SkillRevisionCreated
    SkillRevisionDescriptionDefined
    SkillRevisionInstructionsDefined
    SkillAssetCreated
    SkillAssetPathDefined
    SkillAssetContentDefined
    SkillAssetExecutabilityDefined
    SkillAssetAddedToRevision
    SkillRevisionPublished
  ]
  assert_acceptance(
    (expected_types - facts.map(&:type)).empty?,
    "Granular Skill fact types: #{facts.map(&:type).inspect}"
  )

  content = facts.find { _1.type == "SkillAssetContentDefined" }
  assert_acceptance_equal(%w[asset_id content], content.data.keys.sort, "Content fact data")
  assert_acceptance_equal(
    "utf-8",
    content.metadata.fetch("encoding"),
    "Content fact encoding"
  )
  assert_acceptance_equal("text/x-shellscript", content.metadata.fetch("media_type"), "Content fact media type")
  publication = facts.find { _1.type == "SkillRevisionPublished" }
  assert_acceptance_equal(
    %w[revision skill_id skill_revision_id],
    publication.data.keys.sort,
    "Publication fact data"
  )
end
