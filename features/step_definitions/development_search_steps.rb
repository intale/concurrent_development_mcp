# frozen_string_literal: true

Given("a checkpoint Skill and passive UTF-8 asset have reached the read side") do
  @search_text = "foo Checkpoint BAZ\ncheckpoint foo%_\\bar 'quote'\n日本語 end"
  @search_scope = acceptance_repository_scope
  @search_skill_id = publish_search_skill(name: "checkpoint-guide", scope: @search_scope,
    instructions: @search_text, assets: [ script_asset("scripts/checkpoint.sh", @search_text) ],
    command_id: "search-publish-checkpoint")
  @search_fields = %w[skill.name skill.instructions skill_asset.content].map do |field|
    search_branch(field, search_literal("checkpoint", case_sensitive: false))
  end
end

When("an agent searches their name, instructions and asset content with a page size of {int}") do |limit|
  @search_pages = []
  cursor = nil
  loop do
    page = search_page(@search_fields, limit:, **(cursor ? { cursor: } : {}))
    @search_pages << page
    assert_acceptance(page.fetch("items").length <= limit, "Public page exceeds its mandatory limit")
    break unless page.fetch("has_more")

    cursor = page.fetch("cursor")
    assert_acceptance(cursor, "A continuing page needs an opaque cursor")
    assert_acceptance(@search_pages.length < 5, "Pagination must terminate over this isolated corpus")
  end
end

Then("every search response is immediate, bounded and cursor-followable") do
  assert_acceptance_equal(2, @search_pages.length, "One Skill and one asset produce two bounded pages")
  items = @search_pages.flat_map { _1.fetch("items") }
  keys = items.map { [ _1.fetch("entity_type"), _1.fetch("document_id") ] }
  assert_acceptance_equal(keys.length, keys.uniq.length, "Opaque paging has no duplicate document")
  times = items.map { _1.fetch("updated_at") }
  assert_acceptance_equal(times.sort.reverse, times, "Native update timestamp ordering")
end

Then("overlapping Skill matches identify one Skill, separate from the asset") do
  items = @search_pages.flat_map { _1.fetch("items") }
  assert_acceptance_equal(%w[skill skill_asset], items.map { _1.fetch("entity_type") }.sort, "Canonical document families")
  skill = items.find { _1.fetch("entity_type") == "skill" }
  assert_acceptance_equal(@search_skill_id, skill.fetch("entity_id"), "Skill identity")
  assert_acceptance_equal(%w[skill.instructions skill.name], skill.fetch("matches").map { _1.fetch("field") }, "All matched fields")
end

Then("canonical retrieval returns the exact stored text without execution") do
  @search_pages.flat_map { _1.fetch("items") }.each do |item|
    action = item.fetch("retrieval_actions").sole
    payload = call_tool(action.fetch("tool"), action.fetch("arguments")).dig("result", "structuredContent")
    text = item.fetch("entity_type") == "skill" ? payload.dig("data", "skill", "instructions") : payload.dig("data", "asset", "text")
    assert_acceptance_equal(@search_text, text, "Canonical original text")
    assert_acceptance_equal(1, action.dig("arguments", "revision"), "Pinned available Skill revision")
    assert_acceptance(item.fetch("matches").all? { _1.fetch("excerpt").length <= 240 }, "Bounded passive excerpts")
  end
end

Then("the four match positions and case flags have their declared literal meaning") do
  [
    [ "foo", "starts_with", true, 1 ], [ "FOO", "starts_with", true, 0 ],
    [ "FOO", "starts_with", false, 1 ], [ "end", "ends_with", true, 1 ],
    [ "Checkpoint", "contains", true, 1 ], [ "checkpoint", "equals", false, 0 ],
    [ @search_text, "equals", true, 1 ], [ @search_text.upcase, "equals", false, 1 ]
  ].each do |value, match, case_sensitive, count|
    items = search_page([ search_branch("skill.instructions", search_literal(value, match:, case_sensitive:)) ]).fetch("items")
    assert_acceptance_equal(count, items.length, "#{match} #{value.inspect} case_sensitive=#{case_sensitive}")
  end
  assert_acceptance_equal(0, search_page([ search_branch("skill.instructions", search_literal("FOO", match: "starts_with")) ]).fetch("items").length, "Case-sensitive default")
end

Then("percent, underscore, backslash, newlines and Unicode match as ordinary text") do
  literal = "foo%_\\bar 'quote'\n日本語"
  page = search_page([ search_branch("skill.instructions", search_literal(literal)) ])
  assert_acceptance_equal([ @search_skill_id ], page.fetch("items").map { _1.fetch("entity_id") }, "Raw literal identity")
  assert_acceptance(page.fetch("items").sole.fetch("matches").sole.fetch("excerpt").include?(literal), "Raw unescaped excerpt")
end

Given("equal-name checkpoint Skills in two registered Repository scopes") do
  @search_scoped_ids = %w[home work].to_h do |key|
    register_acceptance_repository(key)
    [ key, publish_search_skill(name: "same-checkpoint", scope: acceptance_repository_scope(key),
      instructions: "checkpoint #{key}", command_id: "search-scope-#{key}") ]
  end
  publish_search_skill(name: "same-checkpoint", scope: "global", instructions: "checkpoint global", command_id: "search-scope-global")
end

Then("scope and Repository filters intersect without global or cross-scope inclusion") do
  fields = [ search_branch("skill.name", search_literal("same-checkpoint", match: "equals")) ]
  %w[home work].each do |key|
    filters = { scope: acceptance_repository_scope(key), repository_id: acceptance_repository_id(key) }
    assert_acceptance_equal([ @search_scoped_ids.fetch(key) ], search_page(fields, filters:).fetch("items").map { _1.fetch("entity_id") }, "Exact #{key} membership")
  end
  filters = { scope: acceptance_repository_scope("home"), repository_id: acceptance_repository_id("work") }
  assert_acceptance_equal([], search_page(fields, filters:).fetch("items"), "Contradictory memberships do not broaden")
end

Given("checkpoint Artifacts with combined, separated and excluded label elements have reached the read side") do
  @search_artifacts = 3.times.map { search_artifact(_1, "checkpoint content #{_1}") }
end

Then("anchored label conjunctions match one element and exclude the prohibited value") do
  expression = { operator: "and", operands: [ search_literal("bar", match: "starts_with"),
    search_literal("baz", match: "ends_with"), { operator: "not", operands: [ search_literal("excluded") ] } ] }
  items = search_page([ search_branch("development_artifact.labels", expression) ]).fetch("items")
  assert_acceptance_equal([ @search_artifacts.first.fetch("artifact_id") ], items.map { _1.fetch("entity_id") }, "Field-local anchored exclusion")
  assert_acceptance_equal("bar middle baz", items.sole.fetch("matches").sole.fetch("excerpt"), "One matched label value")
end

Then("selected title and body fields combine by canonical union") do
  fields = %w[development_artifact.title development_artifact.content].map { search_branch(_1, search_literal("checkpoint")) }
  items = search_page(fields).fetch("items")
  assert_acceptance_equal(@search_artifacts.map { _1.fetch("artifact_id") }.sort, items.map { _1.fetch("entity_id") }.sort, "Canonical union")
  assert_acceptance(items.all? { _1.fetch("matches").map { |match| match.fetch("field") } == %w[development_artifact.content development_artifact.title] }, "Both field evidences are preserved")
  assert_acceptance_equal([], search_page([ search_branch("development_artifact.title", search_literal("checkpoint content")) ]).fetch("items"), "Body cannot complete a title condition")
end

When("the first Artifact is updated through MCP with changed checkpoint text") do
  artifact_id = @search_artifacts.first.fetch("artifact_id")
  revision = artifact_view(artifact_id).dig("data", "artifact", "artifact", "stream_revision")
  outcome = update_artifact_task(command_id: "search-artifact-update", artifact_id:, expected_revision: revision,
    changes: { content: { encoding: "utf-8", media_type: "text/plain", text: "checkpoint replacement" } })
  assert_acceptance_equal("ok", outcome.fetch("status"), "Artifact update Task")
  await_read_model("Updated Artifact head content to become available") do
    payload = artifact_content(artifact_id)
    [ payload.dig("data", "content", "text") == "checkpoint replacement", payload ]
  end
end

Then("its old observation and current text remain distinctly searchable and retrievable") do
  fields = [ search_branch("development_artifact.content", { operator: "or", operands: [
    search_literal("checkpoint content 0", match: "equals"), search_literal("checkpoint replacement", match: "equals")
  ] }) ]
  items = search_page(fields).fetch("items")
  assert_acceptance_equal(2, items.length, "Old observation plus current document")
  texts = items.map do |item|
    action = item.fetch("retrieval_actions").find { _1.fetch("tool") == "development_artifact_content_get" }
    call_tool(action.fetch("tool"), action.fetch("arguments")).dig("result", "structuredContent", "data", "content", "text")
  end
  assert_acceptance_equal([ "checkpoint content 0", "checkpoint replacement" ], texts.sort, "Exact retained content retrieval")
end

Then("search still serves its projected revision 1") do
  fields = [ search_branch("skill.instructions", search_literal("Revision one")) ]
  item = search_page(fields, filters: { scope: @lagging_skill_scope }).fetch("items").sole
  assert_acceptance_equal(1, item.fetch("retrieval_actions").sole.dig("arguments", "revision"), "Stale projection remains available")
end

Then("search returns only the current Skill snapshot") do
  filter = { scope: @lagging_skill_scope }
  old = search_page([ search_branch("skill.instructions", search_literal("Revision one")) ], filters: filter)
  current = search_page([ search_branch("skill.instructions", search_literal("Revision two")) ], filters: filter)
  assert_acceptance_equal([], old.fetch("items"), "Superseded Skill text is removed")
  assert_acceptance_equal(2, current.fetch("items").sole.fetch("retrieval_actions").sole.dig("arguments", "revision"), "Only current revision is searchable")
end

Then("reusing the cursor with a changed exact scope is rejected") do
  response = search_response(@search_fields, limit: 1, cursor: @search_pages.first.fetch("cursor"), filters: { scope: "project:other" })
  assert_acceptance_equal("invalid_cursor", response.dig("result", "structuredContent", "data", "code"), "Query-bound cursor")
end

Then("the public MCP search rejects unknown, short, regex and unanchored requests without a Task") do
  inputs = [
    [ search_branch("unknown.field", search_literal("foo")) ],
    [ search_branch("skill.instructions", search_literal("xy")) ],
    [ search_branch("skill.instructions", search_literal("foo", match: "regex")) ],
    [ search_branch("skill.instructions", search_literal("===")) ],
    [ search_branch("skill.instructions", { operator: "or", operands: [ search_literal("foo"), { operator: "not", operands: [ search_literal("bar") ] } ] }) ]
  ]
  inputs.each do |fields|
    response = search_response(fields)
    assert_acceptance(!response.dig("result", "taskId"), "Invalid Search must not produce a Task")
    invalid = response["error"] || response.dig("result", "isError") == true || response.dig("result", "structuredContent", "status") == "invalid"
    assert_acceptance(invalid, "Explicit validation failure: #{response.inspect}")
  end
end

Given("checkpoint Guidance has reached the read side") do
  task = submit_and_execute("guidance_record", command_id: "search-guidance", actor: { kind: "agent", id: "search-agent" },
    message_id: "search-guidance-message", conversation_id: "search-guidance-conversation", source: "mcp_client",
    text: "checkpoint guidance", anchors: { repository_ids: [ acceptance_repository_id ], change_set_id: nil, work_item_id: nil, attempt_id: nil })
  assert_acceptance_equal(false, task_request("tasks/get", task).dig("result", "result", "isError"), "Guidance Task")
  await_read_model("Search Guidance to become available") do
    payload = call_tool("guidance_get", { message_id: "search-guidance-message" }).dig("result", "structuredContent")
    [ payload.fetch("status") == "ok", payload ]
  end
end

When("the Skills projection table is transactionally locked") do
  locked = Queue.new
  @search_lock_release = Queue.new
  @search_lock_thread = Thread.new do
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.transaction do
        connection.execute("LOCK TABLE skills IN ACCESS EXCLUSIVE MODE")
        locked << true
        @search_lock_release.pop
      end
    end
  end
  locked.pop
  @blocked_search_fields = %w[guidance.text skill.instructions].map { search_branch(_1, search_literal("checkpoint", case_sensitive: false)) }
end

Then("the matching Guidance branch does not hide the whole-page budget failure") do
  payload = search_response(@blocked_search_fields).dig("result", "structuredContent")
  assert_acceptance_equal("search_budget_exceeded", payload.dig("data", "code"), "Whole-page timeout")
  assert_acceptance(!payload.fetch("data").key?("page"), "A failed later branch must not serve partial results")
end

When("the read transaction lock is released") do
  release_search_lock
end

Then("retrying the same search succeeds") do
  items = search_page(@blocked_search_fields).fetch("items")
  assert_acceptance_equal(%w[guidance skill], items.map { _1.fetch("entity_type") }.sort, "Successful complete retry")
end
