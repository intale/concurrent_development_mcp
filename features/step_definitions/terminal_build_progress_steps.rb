# frozen_string_literal: true

Given("terminal Candidate coordination {string} is ready for agent {string}") do |prefix, agent_id|
  @terminal_prefix = prefix
  @terminal_coordination = prepare_terminal_candidate(prefix:, agent_id:)
end

When("the agent submits the final terminal Candidate and releases its write set") do
  @terminal_candidate = submit_terminal_candidate(@terminal_coordination, prefix: @terminal_prefix)
  release_terminal_write_set(@terminal_coordination, prefix: @terminal_prefix)
  ids = @terminal_coordination.fetch(:ids)
  @terminal_available_before_completion = terminal_context(attempt_id: ids.fetch(:attempt_id))
end

Then("available context suggests completing that exact Candidate") do
  action = @terminal_available_before_completion.fetch("next_actions").find do |candidate|
    candidate.fetch("tool") == "work_item_complete"
  end
  assert_acceptance(action, "Available context does not suggest work_item_complete")
  assert_acceptance_equal(
    {
      "change_set_id" => @terminal_coordination.dig(:ids, :change_set_id),
      "work_item_id" => @terminal_coordination.dig(:ids, :work_item_id),
      "attempt_id" => @terminal_coordination.dig(:ids, :attempt_id),
      "candidate_id" => @terminal_candidate.dig(:arguments, :candidate_id)
    },
    action.fetch("arguments"),
    "Terminal completion suggestion"
  )
end

When("the agent completes the WorkItem through an MCP Task") do
  @terminal_completion = complete_terminal_work_item(
    @terminal_coordination,
    @terminal_candidate,
    prefix: @terminal_prefix
  )
end

Then("the terminal Task records one selected Candidate, completed Attempt, and completed WorkItem") do
  ids = @terminal_coordination.fetch(:ids)
  state = @terminal_completion.fetch(:state)
  assert_acceptance_equal("completed", state.dig("result", "status"), "Terminal Task status")
  assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Terminal Task error")
  assert_acceptance_equal(
    %w[WorkItemCandidateSelected WorkItemCompleted],
    terminal_work_item_events(ids.fetch(:work_item_id)).map(&:type),
    "Terminal WorkItem facts"
  )
  assert_acceptance_equal(
    [ "AttemptCompleted" ],
    terminal_attempt_events(ids.fetch(:attempt_id)).select { _1.type == "AttemptCompleted" }.map(&:type),
    "Terminal Attempt facts"
  )
end

Then("the older acquired context remains available before terminal projection") do
  ids = @terminal_coordination.fetch(:ids)
  lagging = terminal_context(attempt_id: ids.fetch(:attempt_id))
  context = lagging.dig("data", "context")
  assert_acceptance_equal("ok", lagging.fetch("status"), "Lagging terminal context status")
  assert_acceptance_equal(
    @terminal_available_before_completion.fetch("context_token"),
    lagging.fetch("context_token"),
    "Lagging terminal context token"
  )
  assert_acceptance_equal("acquired", context.fetch("work_items").sole.fetch("status"), "Lagging WorkItem")
  assert_acceptance(
    (lagging.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Lagging terminal context must not expose a freshness gate"
  )
end

When("terminal facts and build progress reach the read side") do
  ids = @terminal_coordination.fetch(:ids)
  work_item_events = terminal_work_item_events(ids.fetch(:work_item_id))
  attempt_completed = terminal_attempt_events(ids.fetch(:attempt_id)).find { _1.type == "AttemptCompleted" }
  projector = Coordinator::Container["projectors.coord_context_v1"]
  projector.call(work_item_events.find { _1.type == "WorkItemCandidateSelected" })
  projector.call(attempt_completed)
  completion = work_item_events.find { _1.type == "WorkItemCompleted" }
  projector.call(completion)
  Coordinator::Container["process_managers.build_progress"].call(completion)
  projector.call(terminal_change_set_events(ids.fetch(:change_set_id)).sole)
  @terminal_converged_context = terminal_context(change_set_id: ids.fetch(:change_set_id))
end

Then(
  "available context exposes the completed WorkItem, Attempt, and ChangeSet without a freshness gate"
) do
  payload = @terminal_converged_context
  context = payload.dig("data", "context")
  candidate_id = @terminal_candidate.dig(:arguments, :candidate_id)
  assert_acceptance_equal("completed", context.dig("change_set", "status"), "ChangeSet status")
  assert_acceptance_equal("completed", context.fetch("work_items").sole.fetch("status"), "WorkItem status")
  assert_acceptance_equal(candidate_id, context.fetch("work_items").sole.fetch("selected_candidate_id"), "Selection")
  assert_acceptance_equal("completed", context.fetch("attempts").sole.fetch("status"), "Attempt status")
  assert_acceptance_equal(candidate_id, context.fetch("attempts").sole.fetch("selected_candidate_id"), "Attempt result")
  assert_acceptance_equal([], payload.fetch("next_actions"), "Completed next actions")
  assert_acceptance(
    (payload.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Converged terminal context must not expose a freshness gate"
  )
end

Given("terminal coordination {string} has a consumer blocked on producer completion") do |prefix|
  @dependency_prefix = prefix
  @dependency_terminal = prepare_terminal_dependency(prefix:)
  ids = @dependency_terminal.fetch(:ids)
  @dependency_blocked_context = terminal_context(work_item_id: ids.fetch(:consumer_work_item_id))
end

When("the producer completes through an MCP Task and build progress handles its completion") do
  coordination = @dependency_terminal.fetch(:candidate_coordination)
  @dependency_candidate = submit_terminal_candidate(coordination, prefix: @dependency_prefix)
  release_terminal_write_set(coordination, prefix: @dependency_prefix)
  @dependency_completion = complete_terminal_work_item(
    coordination,
    @dependency_candidate,
    prefix: @dependency_prefix
  )
  ids = @dependency_terminal.fetch(:ids)
  @dependency_context_before_progress = terminal_context(
    work_item_id: ids.fetch(:consumer_work_item_id)
  )
  source = terminal_work_item_events(coordination.dig(:ids, :work_item_id)).find do |event|
    event.type == "WorkItemCompleted"
  end
  Coordinator::Container["process_managers.build_progress"].call(source)
end

Then("the consumer's older blocked context remains available") do
  ids = @dependency_terminal.fetch(:ids)
  lagging = terminal_context(work_item_id: ids.fetch(:consumer_work_item_id))
  assert_acceptance_equal("ok", lagging.fetch("status"), "Lagging dependency context status")
  assert_acceptance_equal(
    @dependency_context_before_progress.fetch("context_token"),
    lagging.fetch("context_token"),
    "Lagging dependency context token"
  )
  assert_acceptance_equal(1, lagging.dig("data", "blockers").length, "Lagging blockers")
end

When("dependency satisfaction reaches the read side before readiness") do
  ids = @dependency_terminal.fetch(:ids)
  event = terminal_dependency_events(ids.fetch(:change_set_id)).sole
  Coordinator::Container["projectors.coord_context_v1"].call(event)
  @dependency_partially_converged = terminal_context(work_item_id: ids.fetch(:consumer_work_item_id))
end

Then("the blocker is absent while the consumer is still observed as planned") do
  ids = @dependency_terminal.fetch(:ids)
  payload = @dependency_partially_converged
  consumer = payload.dig("data", "context", "work_items").find do |work_item|
    work_item.fetch("work_item_id") == ids.fetch(:consumer_work_item_id)
  end
  assert_acceptance_equal([], payload.dig("data", "blockers"), "Observed blockers")
  assert_acceptance_equal("planned", consumer.fetch("status"), "Partially converged consumer")
  consumer_actions = payload.fetch("next_actions").select do |action|
    action.fetch("tool") == "work_item_acquire" &&
      action.dig("arguments", "work_item_id") == ids.fetch(:consumer_work_item_id)
  end
  assert_acceptance_equal([], consumer_actions, "Partially converged consumer actions")
end

When("downstream readiness reaches the read side") do
  ids = @dependency_terminal.fetch(:ids)
  event = terminal_readiness_events(ids.fetch(:consumer_work_item_id)).sole
  Coordinator::Container["projectors.coord_context_v1"].call(event)
  @dependency_converged = terminal_context(work_item_id: ids.fetch(:consumer_work_item_id))
end

Then("available context suggests acquiring the exact consumer WorkItem") do
  ids = @dependency_terminal.fetch(:ids)
  action = @dependency_converged.fetch("next_actions").find { _1.fetch("tool") == "work_item_acquire" }
  assert_acceptance(action, "Available context does not suggest work_item_acquire")
  assert_acceptance_equal(
    {
      "change_set_id" => ids.fetch(:change_set_id),
      "work_item_id" => ids.fetch(:consumer_work_item_id)
    },
    action.fetch("arguments"),
    "Consumer acquisition suggestion"
  )
end
