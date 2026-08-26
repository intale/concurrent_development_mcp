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
      project_skill_event(event)
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
  project_skill_event(skill_events(name:, scope:).sole)
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

Then("the stale Skill Task completes with revision conflict and no command fact") do
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
    [],
    command_events(@stale_skill_publication.fetch(:command_id)),
    "Stale command facts"
  )
end

When("Skill revision 2 reaches the read side") do
  project_skill_event(skill_events(name: @lagging_skill_name, scope: @lagging_skill_scope).last)
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
  project_skill_event(skill_events(name: @asset_skill_name, scope: @asset_skill_scope).sole)
end

Then("the exact script asset content and digest are available through MCP") do
  payload = skill_asset(name: @asset_skill_name, scope: @asset_skill_scope, path: @asset_path)
  asset = payload.dig("data", "asset")
  assert_acceptance_equal("ok", payload.fetch("status"), "Asset query status")
  assert_acceptance_equal([ @asset_content ].pack("m0"), asset.fetch("content_base64"), "Asset content")
  assert_acceptance(
    asset.fetch("content_sha256").match?(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN),
    "Asset digest must be a SHA-256 digest"
  )
end

Then("the Skill view exposes the asset manifest without embedding its content") do
  skill = skill_view(name: @asset_skill_name, scope: @asset_skill_scope).dig("data", "skill")
  manifest = skill.fetch("assets").sole
  assert_acceptance_equal(@asset_path, manifest.fetch("path"), "Manifest path")
  assert_acceptance(!manifest.key?("content_base64"), "Skill manifest must not embed asset content")
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
  skill_events(name:, scope:).each { project_skill_event(_1) }
end

When("the agent retrieves Skill {string} revision 1 and follows its asset manifest") do |name|
  @historical_skill_view = skill_view(
    name:,
    scope: @historical_skill_scope,
    revision: 1
  )
  manifest = @historical_skill_view.dig("data", "skill", "assets").sole
  @historical_skill_asset = skill_asset(
    name:,
    scope: @historical_skill_scope,
    revision: 1,
    path: manifest.fetch("path")
  )
end

Then("the Skill metadata, manifest, and asset content all describe revision 1") do
  skill = @historical_skill_view.dig("data", "skill")
  manifest = skill.fetch("assets").sole
  asset = @historical_skill_asset.dig("data", "asset")

  assert_acceptance_equal("ok", @historical_skill_view.fetch("status"), "Historical Skill status")
  assert_acceptance_equal("ok", @historical_skill_asset.fetch("status"), "Historical asset status")
  assert_acceptance_equal(1, skill.fetch("revision"), "Historical Skill revision")
  assert_acceptance_equal(1, asset.fetch("revision"), "Historical asset revision")
  assert_acceptance_equal(manifest.fetch("content_sha256"), asset.fetch("content_sha256"), "Pinned digest")
  assert_acceptance_equal(
    [ @historical_asset_content ].pack("m0"),
    asset.fetch("content_base64"),
    "Pinned asset content"
  )
end

Then("retrieving Skill {string} without a revision returns revision 2") do |name|
  payload = skill_view(name:, scope: @historical_skill_scope || @replayed_skill_scope)
  assert_acceptance_equal("ok", payload.fetch("status"), "Current Skill status")
  assert_acceptance_equal(2, payload.dig("data", "skill", "revision"), "Current Skill revision")
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

When("Skill revision 2 reaches the read side before revision 1 and both deliveries are repeated") do
  first_event, second_event = skill_events(name: @replayed_skill_name, scope: @replayed_skill_scope)
  [ second_event, second_event, first_event, first_event ].each { project_skill_event(_1) }
end

Then("both historical Skill revisions remain retrievable") do
  revisions = [ 1, 2 ].map do |revision|
    skill_view(name: @replayed_skill_name, scope: @replayed_skill_scope, revision:)
      .dig("data", "skill", "revision")
  end
  assert_acceptance_equal([ 1, 2 ], revisions, "Historical Skill revisions")
end
