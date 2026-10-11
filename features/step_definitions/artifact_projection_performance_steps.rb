# frozen_string_literal: true

Given("a large passive Artifact and its original observation have reached the read side") do
  @large_artifact_text = "preserved large evidence\n" * 50_000
  @large_artifact_capture = capture_artifact_task(
    command_id: "large-artifact-capture", title: "Original large evidence", kind: "documentation",
    labels: %w[evidence original], locator: "evidence/large.md", source_kind: "local_file",
    revision: "large-original-revision",
    content: { encoding: "utf-8", media_type: "text/markdown", text: @large_artifact_text }
  ).fetch("data")
  @large_artifact_id = @large_artifact_capture.fetch("artifact_id")
  @large_original_view = project_artifact(
    @large_artifact_id, observation_id: @large_artifact_capture.fetch("observation_id")
  ).dig("data", "artifact", "artifact")
end

When("the agent corrects only its title and labels and replays the same MCP command") do
  arguments = {
    command_id: "large-artifact-metadata-update", actor: { kind: "agent", id: "artifact-agent" },
    observation_id: @large_artifact_capture.fetch("observation_id"), expected_revision: 1,
    title: "Updated large evidence", kind: "documentation", labels: %w[evidence optimized],
    reason: "Correct the classification without changing the original evidence."
  }
  @large_artifact_tasks = 2.times.map { submit_and_execute("development_artifact_classification_correct", **arguments) }
  @large_artifact_update = task_request("tasks/get", @large_artifact_tasks.first)
    .dig("result", "result", "structuredContent")
  assert_acceptance_equal("ok", @large_artifact_update.fetch("status"), "Metadata update Task")
end

When("the changed Artifact observation reaches the read side after a subscription restart") do
  restart_read_model_subscriptions
  @large_updated_view = await_read_model("Updated large Artifact observation") do
    payload = artifact_view(@large_artifact_id)
    artifact = payload.dig("data", "artifact", "artifact")
    ready = artifact && artifact.fetch("title") == "Updated large evidence" &&
      artifact.fetch("labels") == %w[evidence optimized] &&
      artifact.fetch("classification_revision") == 2
    [ ready, payload ]
  end.dig("data", "artifact", "artifact")
end

Then("one metadata update Task and one command lifecycle exist") do
  assert_acceptance_equal(1, @large_artifact_tasks.uniq.length, "Replay Task identity")
  assert_acceptance_equal(%w[CommandRegistered CommandSucceeded],
    command_events("large-artifact-metadata-update").map(&:type), "Replay command lifecycle")
  facts = artifact_events(@large_artifact_id)
  assert_acceptance_equal(1, facts.count { _1.type == "DevelopmentArtifactContentChanged" }, "No repeated content fact")
  assert_acceptance_equal(1, facts.count { _1.type == "DevelopmentArtifactSourceChanged" }, "No repeated provenance fact")
  assert_acceptance_equal(2, facts.count { _1.type == "DevelopmentArtifactTitleChanged" }, "Exactly one new title fact")
end

Then("its body and original provenance remain byte-exact") do
  observation = artifact_view(@large_artifact_id, observation_id: @large_artifact_capture.fetch("observation_id"))
    .dig("data", "artifact", "artifact")
  [ observation, @large_updated_view ].each do |view|
    assert_acceptance_equal(@large_original_view.fetch("source"), view.fetch("source"), "Unchanged provenance")
    assert_acceptance_equal(@large_original_view.fetch("content_sha256"), view.fetch("content_sha256"), "Unchanged content digest")
    content = artifact_content(@large_artifact_id, observation_id: view.fetch("observation_id"))
    assert_acceptance_equal(@large_artifact_text, content.dig("data", "content", "text"), "Exact passive body")
  end
  assert_acceptance_equal(@large_artifact_text, artifact_content(@large_artifact_id).dig("data", "content", "text"), "Current head body")
end

Then("search exposes the current labels and their native update timestamp") do
  fields = [ search_branch("development_artifact.labels", search_literal("optimized", match: "equals")) ]
  items = await_read_model("Updated label search") do
    page = search_page(fields)
    [ page.fetch("items").length == 1, page.fetch("items") ]
  end
  item = items.sole
  assert_acceptance_equal("current:#{@large_artifact_id}", item.fetch("document_id"), "Current search identity")
  observation_id = @large_updated_view.fetch("observation_id")
  source_time = artifact_observation_events(observation_id).map(&:created_at).max.utc.iso8601(6)
  assert_acceptance_equal(source_time, item.fetch("updated_at"), "Native observation update time")
  assert_acceptance_equal("optimized", item.fetch("matches").sole.fetch("excerpt"), "Exact raw label")
end
