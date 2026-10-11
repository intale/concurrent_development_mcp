# frozen_string_literal: true

When("the agent submits a private Skill while the workers are stopped") do
  stop_live_subscriptions
  reset_observed_telemetry
  @observed_publication = observed_skill_publication(command_id: "cuc-observability-publish")
end

Then("telemetry reports acceptance while the Task remains working") do
  publication = @observed_publication
  state = task_request("tasks/get", publication.fetch(:task_id), client_id: publication.fetch(:client_id))
  assert_acceptance_equal("working", state.dig("result", "status"), "Accepted Task state")
  assert_observed_outcome(method: "tools/call", tool: "skill_publish", outcome: "accepted")
  assert_observed_outcome(method: "tasks/get", outcome: "pending")
  assert_acceptance(observed_spans.none? { _1.kind == :consumer }, "No handler should execute before worker start")
end

When("the real subscription workers process the observed Task") do
  start_live_subscriptions
  publication = @observed_publication
  @observed_task_state = await_task_terminal(publication.fetch(:task_id), client_id: publication.fetch(:client_id))
end

Then("the Skill is available unchanged through the MCP read side") do
  assert_acceptance_equal("completed", @observed_task_state.dig("result", "status"), "Observed Task status")
  assert_acceptance_equal("ok", @observed_task_state.dig("result", "result", "structuredContent", "status"), "Publication outcome")
  projected = await_read_model("observed Skill projection") do
    payload = skill_view(name: ObservabilityAcceptanceWorld::SKILL_NAME, scope: ObservabilityAcceptanceWorld::SKILL_SCOPE)
    [ payload.dig("data", "skill", "instructions") == ObservabilityAcceptanceWorld::PRIVATE_INSTRUCTIONS, payload ]
  end
  assert_acceptance_equal(1, projected.dig("data", "skill", "revision"), "Projected Skill revision")
end

Then("telemetry records all three subscription sets and their Rails SQL") do
  handlers = observed_spans.select { _1.kind == :consumer }
  expected_sets = %w[coordinator-process-managers-v1 coordinator-task-results-v1 coordinator-read-models-v1]
  actual_sets = handlers.map { _1.attributes.fetch("subscription.set") }.uniq
  assert_acceptance_equal(expected_sets.sort, actual_sets.sort, "Observed subscription sets")
  handler_ids = handlers.map(&:span_id)
  assert_acceptance(
    observed_spans.any? { _1.name.start_with?("SQL ") && handler_ids.include?(_1.parent_span_id) },
    "A real Rails SQL span must be a child of its handler"
  )
end

Given("the observed Skill has already been published") do
  @observed_initial_publication = observed_skill_publication(command_id: "cuc-observability-initial")
  start_live_subscriptions
  publication = @observed_initial_publication
  state = await_task_terminal(publication.fetch(:task_id), client_id: publication.fetch(:client_id))
  assert_acceptance_equal("ok", state.dig("result", "result", "structuredContent", "status"), "Initial Skill publication")
end

When("the agent submits the observed Skill with a stale revision") do
  @observed_publication = observed_skill_publication(command_id: "cuc-observability-stale")
end

Then("the Task returns the original revision conflict through MCP") do
  publication = @observed_publication
  state = await_task_terminal(publication.fetch(:task_id), client_id: publication.fetch(:client_id))
  assert_acceptance_equal("completed", state.dig("result", "status"), "Rejected Task status")
  result = state.dig("result", "result", "structuredContent")
  assert_acceptance_equal("conflict", result.fetch("status"), "Revision conflict outcome")
  assert_acceptance_equal("skill_revision_conflict", result.dig("data", "code"), "Revision conflict reason")
end

Then("telemetry separates the conflict from successful handler delivery") do
  assert_observed_outcome(method: "tools/call", tool: "skill_publish", outcome: "accepted")
  assert_observed_outcome(method: "tasks/get", outcome: "conflict")
  executors = observed_spans.select do |span|
    span.kind == :consumer && span.attributes.fetch("subscription.name").start_with?("coordination-task-executor-lane-")
  end
  assert_acceptance(!executors.empty? && executors.all? { _1.attributes.fetch("outcome") == "ok" && _1.status.ok? },
    "Business rejection must not become a technical handler error")
end

When("the agent cancels the observed Task through MCP") do
  publication = @observed_publication
  @observed_cancel = task_request("tasks/cancel", publication.fetch(:task_id), client_id: publication.fetch(:client_id))
end

Then("the original cancellation acknowledgement and status are preserved") do
  publication = @observed_publication
  state = task_request("tasks/get", publication.fetch(:task_id), client_id: publication.fetch(:client_id))
  assert_acceptance_equal({ "resultType" => "complete" }, @observed_cancel.fetch("result"), "Cancellation acknowledgement")
  assert_acceptance_equal("cancelled", state.dig("result", "status"), "Cancelled Task status")
end

Then("telemetry reports cancellation without publishing the Task identity") do
  assert_observed_outcome(method: "tasks/get", outcome: "cancelled")
end

Then("finished telemetry has bounded dimensions and no private payloads") do
  assert_observed_privacy_and_dimensions
end
