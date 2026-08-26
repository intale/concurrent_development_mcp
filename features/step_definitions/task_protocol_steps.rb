# frozen_string_literal: true

Given("an MCP agent supports checkpointed Tasks") do
  self.tasks_capable = true
end

Given("an MCP client does not support checkpointed Tasks") do
  self.tasks_capable = false
end

When("agent {string} submits ChangeSet {string} with command {string}") do |agent_id, change_set_id, command_id|
  @current_tool = "change_set_create"
  @current_arguments = {
    command_id:,
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    goal: "Coordinate #{change_set_id}",
    acceptance_criteria: [ "Agents do not overlap" ]
  }
  @current_response = call_tool(@current_tool, @current_arguments)
  @current_task_id = @current_response.dig("result", "taskId")
end

Then("the Task is durable before coordination begins") do
  assert_acceptance(
    @current_task_id&.match?(Coordinator::Shared::Types::UUID_V7_PATTERN),
    "The server did not return a UUIDv7 Task handle"
  )
  assert_acceptance_equal(
    [ "CoordinationTaskSubmitted" ],
    task_events(@current_task_id).map(&:type),
    "Persisted Task history before execution"
  )
  assert_acceptance_equal([], command_events(@current_arguments.fetch(:command_id)), "Command facts")
  assert_acceptance_equal([], change_set_events(@current_arguments.fetch(:change_set_id)), "ChangeSet facts")
end

When("the Task executor processes the current Task") do
  execute_task(@current_task_id)
end

When("the current Task completes through live subscriptions") do
  start_live_subscriptions
  await_task_terminal(@current_task_id)
end

Then("the current Task completes successfully") do
  @current_task_state = task_request("tasks/get", @current_task_id)
  assert_acceptance_equal("completed", @current_task_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(false, @current_task_state.dig("result", "result", "isError"), "Tool error flag")
  @first_task_id ||= @current_task_id
  @first_task_result ||= @current_task_state.dig("result", "result")
end

When("the same command is retried and processed through another Task") do
  @retry_response = call_tool(@current_tool, @current_arguments)
  @retry_task_id = @retry_response.dig("result", "taskId")
  assert_acceptance(@retry_task_id != @first_task_id, "A retry should receive a new Task handle")
  execute_task(@retry_task_id)
end

When("the same command is retried through another live Task") do
  @retry_task_id = submit_and_await(@current_tool, **@current_arguments)
  assert_acceptance(@retry_task_id != @first_task_id, "A retry should receive a new Task handle")
end

Then("both Task handles expose the same result") do
  retry_state = task_request("tasks/get", @retry_task_id)
  assert_acceptance_equal("completed", retry_state.dig("result", "status"), "Retry Task status")
  assert_acceptance_equal(
    @first_task_result,
    retry_state.dig("result", "result"),
    "Original and retry results"
  )
end

Then("the command and ChangeSet facts exist only once") do
  assert_acceptance_equal(1, command_events(@current_arguments.fetch(:command_id)).length, "Command completions")
  assert_acceptance_equal(2, change_set_events(@current_arguments.fetch(:change_set_id)).length, "ChangeSet facts")
end

When("the completed command identity is submitted with a changed ChangeSet goal") do
  changed = @current_arguments.merge(goal: "A different goal for the same command identity")
  @current_response = call_tool(@current_tool, changed)
  @current_task_id = @current_response.dig("result", "taskId")
end

Then("only the original command and ChangeSet facts remain") do
  assert_acceptance_equal(1, command_events(@current_arguments.fetch(:command_id)).length, "Command completions")
  assert_acceptance_equal(2, change_set_events(@current_arguments.fetch(:change_set_id)).length, "ChangeSet facts")
end

When("the successful command receipt reaches the read side") do
  completion = command_events(@current_arguments.fetch(:command_id)).sole
  Coordinator::Container["projectors.command_receipts_v1"].call(completion)
  @operation_response = call_tool(
    "operation_get",
    { command_id: @current_arguments.fetch(:command_id) }
  )
end

Then("operation_get exposes the receipt without a freshness claim") do
  payload = @operation_response.dig("result", "structuredContent")

  assert_acceptance_equal("ok", payload.fetch("status"), "Operation status")
  assert_acceptance_equal(@current_arguments.fetch(:command_id), payload.fetch("receipt"), "Operation receipt")
  assert_acceptance(
    (payload.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Operation query must not claim freshness"
  )
end

When(
  "agent {string} submits WorkItem {string} to missing ChangeSet {string} with command {string}"
) do |agent_id, work_item_id, change_set_id, command_id|
  @current_tool = "work_item_create"
  @current_arguments = work_item_arguments(
    agent_id:,
    work_item_id:,
    change_set_id:,
    command_id:
  )
  @current_response = call_tool(@current_tool, @current_arguments)
  @current_task_id = @current_response.dig("result", "taskId")
end

Then("the current Task completes with coordination denial {string}") do |code|
  state = task_request("tasks/get", @current_task_id)
  assert_acceptance_equal("completed", state.dig("result", "status"), "Denied Task status")
  assert_acceptance_equal(true, state.dig("result", "result", "isError"), "Denied result error flag")
  assert_acceptance_equal(
    code,
    state.dig("result", "result", "structuredContent", "data", "code"),
    "Denial code"
  )
end

Then("the denied command writes no coordination facts") do
  assert_no_current_coordination_facts
end

When("the agent cancels the current Task before execution") do
  @cancel_response = task_request("tasks/cancel", @current_task_id)
end

When("the Task executor later receives the cancelled Task") do
  execute_task(@current_task_id)
end

Then("the current Task is cancelled") do
  state = task_request("tasks/get", @current_task_id)
  assert_acceptance_equal({ "resultType" => "complete" }, @cancel_response.fetch("result"), "Cancel acknowledgement")
  assert_acceptance_equal("cancelled", state.dig("result", "status"), "Cancelled Task status")
end

Then("the cancelled command writes no coordination facts") do
  assert_no_current_coordination_facts
end

Given("the read side has projected ChangeSet {string}") do |change_set_id|
  arguments = {
    command_id: "cmd-project-#{change_set_id}",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    goal: "Coordinate #{change_set_id}",
    acceptance_criteria: [ "Serve available context while projections lag" ]
  }
  task_id = call_tool("change_set_create", arguments).dig("result", "taskId")
  execute_task(task_id)
  project_change_set(change_set_id)
  @stale_change_set_id = change_set_id
  @projected_context = call_tool("coord_context", { change_set_id: })
end

When(
  "agent {string} completes WorkItem {string} with command {string} without projecting it"
) do |agent_id, work_item_id, command_id|
  @current_tool = "work_item_create"
  @current_arguments = work_item_arguments(
    agent_id:,
    work_item_id:,
    change_set_id: @stale_change_set_id,
    command_id:
  )
  @current_task_id = call_tool(@current_tool, @current_arguments).dig("result", "taskId")
  execute_task(@current_task_id)
  @stale_context_response = call_tool("coord_context", { change_set_id: @stale_change_set_id })
end

Then("the agent can still read the previous ChangeSet context") do
  payload = @stale_context_response.dig("result", "structuredContent")
  assert_acceptance_equal("ok", payload.fetch("status"), "Available context status")
  assert_acceptance_equal(
    @projected_context.dig("result", "structuredContent", "context_token"),
    payload.fetch("context_token"),
    "Context token while projection lags"
  )
  assert_acceptance(!payload.key?("projection_status"), "Context must not expose a freshness gate")
end

Then("the newer WorkItem exists only on the write side of that response") do
  work_item_id = @current_arguments.fetch(:work_item_id)
  payload = @stale_context_response.dig("result", "structuredContent")
  work_items = payload.dig("data", "context", "work_items")
  assert_acceptance_equal(1, work_item_events(work_item_id).length, "Persisted WorkItem facts")
  assert_acceptance_equal([], work_items, "Lagging projected WorkItems")
end

When("agent {string} attempts ChangeSet {string} with command {string}") do |agent_id, change_set_id, command_id|
  @current_arguments = {
    command_id:,
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    goal: "Coordinate #{change_set_id}",
    acceptance_criteria: [ "Tasks are mandatory" ]
  }
  @current_response = call_tool("change_set_create", @current_arguments)
end

Then("the server requires the Tasks extension") do
  assert_acceptance_equal(-32_003, @current_response.dig("error", "code"), "Capability error code")
  assert_acceptance_equal(
    { McpAcceptanceWorld::TASKS_EXTENSION => {} },
    @current_response.dig("error", "data", "requiredCapabilities", "extensions"),
    "Required Tasks capability"
  )
end

Then("the rejected request writes no coordination facts") do
  assert_acceptance_equal(
    [],
    task_events_for_command(@current_arguments.fetch(:command_id)),
    "Rejected Task submissions"
  )
  assert_no_current_coordination_facts
end
