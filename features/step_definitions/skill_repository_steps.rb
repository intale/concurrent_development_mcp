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
