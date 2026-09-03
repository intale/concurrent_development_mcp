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
  submitted = task_events(@current_task_id).sole
  assert_acceptance_equal("CoordinationTaskSubmitted", submitted.type, "Persisted Task fact")
  assert_acceptance_equal(3, submitted.metadata.fetch("schema_version"), "Task submission schema")
  assert_acceptance(
    !submitted.data.key?("canonical_input_digest"),
    "Task submission must not duplicate a digest derivable from command_input"
  )
  assert_acceptance(submitted.data.key?("command_input"), "Task submission command input is missing")
  assert_command_registered(@current_arguments.fetch(:command_id), context: "Durable command registration")
  assert_acceptance_equal([], change_set_events(@current_arguments.fetch(:change_set_id)), "ChangeSet facts")
end

Then("the completed Task has a lean terminal linked to one successful command") do
  assert_semantic_task_completion(@current_task_id, kind: "success")
end

Then("the completed Task has a lean terminal linked to one rejected command") do
  assert_semantic_task_completion(@current_task_id, kind: "domain_rejection")
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

When("the same command is retried and resolves to its original Task") do
  @retry_response = call_tool(@current_tool, @current_arguments)
  @retry_task_id = @retry_response.dig("result", "taskId")
  assert_acceptance_equal(@first_task_id, @retry_task_id, "Replayed Task identity")
end

When("the same command is retried through its original live Task") do
  @retry_task_id = submit_and_await(@current_tool, **@current_arguments)
  assert_acceptance_equal(@first_task_id, @retry_task_id, "Replayed Task identity")
end

Given(
  "agent {string} completed ChangeSet {string} with command {string} through live subscriptions"
) do |agent_id, change_set_id, command_id|
  @current_tool = "change_set_create"
  @current_arguments = {
    command_id:,
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    goal: "Coordinate #{change_set_id}",
    acceptance_criteria: [ "Recover the durable Task result" ]
  }
  start_live_subscriptions
  @original_task_id = submit_and_await(@current_tool, **@current_arguments)
  @original_task_state = task_request("tasks/get", @original_task_id)
end

Given("the Task workers are interrupted") do
  start_live_subscriptions unless @live_subscription_sets
  stop_live_subscriptions
end

When("the exact completed command request is retried") do
  response = call_tool(@current_tool, @current_arguments)
  @replayed_task_id = response.dig("result", "taskId")
  @current_task_id = @replayed_task_id
end

Then("the retry returns the original completed Task without duplicate coordination facts") do
  state = task_request("tasks/get", @replayed_task_id)
  assert_acceptance_equal(@original_task_id, @replayed_task_id, "Replayed Task identity")
  assert_acceptance_equal("completed", state.dig("result", "status"), "Replayed Task status")
  assert_command_succeeded(@current_arguments.fetch(:command_id), context: "Recovered command lifecycle")
  assert_acceptance_equal(
    2,
    change_set_events(@current_arguments.fetch(:change_set_id)).length,
    "ChangeSet facts"
  )
end

When("the Task workers restart") do
  start_live_subscriptions
end

Then("the replayed Task exposes the original completed result") do
  replayed = await_task_terminal(@replayed_task_id)
  assert_acceptance_equal("completed", replayed.dig("result", "status"), "Replayed status")
  assert_acceptance_equal(
    @original_task_state.dig("result", "result"),
    replayed.dig("result", "result"),
    "Recovered Task result"
  )
end

Then("an independent MCP client reconstructs the same terminal result") do
  prepare_mcp_clients("semantic-task-reader")
  independent = task_request(
    "tasks/get",
    @replayed_task_id,
    client_id: "semantic-task-reader"
  )
  expected = task_request("tasks/get", @replayed_task_id)

  assert_acceptance_equal(
    expected.dig("result", "result"),
    independent.dig("result", "result"),
    "Independently reconstructed terminal result"
  )
end

Then("the recovered command and ChangeSet facts exist only once") do
  assert_command_succeeded(@current_arguments.fetch(:command_id), context: "Recovered command lifecycle")
  assert_acceptance_equal(
    2,
    change_set_events(@current_arguments.fetch(:change_set_id)).length,
    "ChangeSet facts"
  )
end

Then("the current Task remains working before the worker restarts") do
  state = task_request("tasks/get", @current_task_id)
  assert_acceptance_equal("working", state.dig("result", "status"), "Interrupted Task status")
end

Then("the current Task eventually completes successfully") do
  state = await_task_terminal(@current_task_id)
  assert_acceptance_equal("completed", state.dig("result", "status"), "Restarted Task status")
  assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Tool error flag")
end

Then("the replayed Task exposes the same result") do
  retry_state = task_request("tasks/get", @retry_task_id)
  assert_acceptance_equal("completed", retry_state.dig("result", "status"), "Retry Task status")
  assert_acceptance_equal(
    @first_task_result,
    retry_state.dig("result", "result"),
    "Original and retry results"
  )
end

Then("the command and ChangeSet facts exist only once") do
  assert_command_succeeded(@current_arguments.fetch(:command_id), context: "Command lifecycle")
  assert_acceptance_equal(2, change_set_events(@current_arguments.fetch(:change_set_id)).length, "ChangeSet facts")
end

When("the completed command identity is submitted with a changed ChangeSet goal") do
  changed = @current_arguments.merge(goal: "A different goal for the same command identity")
  @current_response = call_tool(@current_tool, changed, expected_status: 400)
end

Then("the changed request is rejected immediately with command identity conflict") do
  assert_acceptance_equal(-32_602, @current_response.dig("error", "code"), "JSON-RPC error")
  assert_acceptance_equal(
    "command_id_reused",
    @current_response.dig("error", "data", "code"),
    "Command identity conflict"
  )
end

Then("only the original command and ChangeSet facts remain") do
  assert_command_succeeded(@current_arguments.fetch(:command_id), context: "Original command lifecycle")
  assert_acceptance_equal(2, change_set_events(@current_arguments.fetch(:change_set_id)).length, "ChangeSet facts")
end

When("the successful command receipt reaches the read side") do
  command_id = @current_arguments.fetch(:command_id)
  @operation_response = await_read_model("Command receipt #{command_id} to become available") do
    response = call_tool("operation_get", { command_id: })
    payload = response.dig("result", "structuredContent")
    [ payload["status"] == "ok" && payload["receipt"] == command_id, response ]
  end
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

When("agent {string} submits the same ChangeSet with command {string}") do |agent_id, command_id|
  @current_arguments = @current_arguments.merge(
    command_id:,
    actor: { kind: "agent", id: agent_id }
  )
  @current_response = call_tool(@current_tool, @current_arguments)
  @current_task_id = @current_response.dig("result", "taskId")
end

Then("the current Task eventually completes with coordination denial {string}") do |code|
  state = await_task_terminal(@current_task_id)
  assert_acceptance_equal("completed", state.dig("result", "status"), "Denied Task status")
  assert_acceptance_equal(true, state.dig("result", "result", "isError"), "Denied result error flag")
  assert_acceptance_equal(
    code,
    state.dig("result", "result", "structuredContent", "data", "code"),
    "Denial code"
  )
end

Then("the denied command writes no target coordination facts") do
  assert_command_rejected(@current_arguments.fetch(:command_id), context: "Denied command lifecycle")
  assert_no_current_target_facts
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

Then("the cancelled command writes no target coordination facts") do
  assert_command_registered(@current_arguments.fetch(:command_id), context: "Cancelled command lifecycle")
  assert_no_current_target_facts
end

When("a Task worker restarts and reaches the durable execution boundary") do
  install_contention_barrier(
    operation: "coordination_task_execute",
    command_ids: [ task_command_id(@current_task_id) ]
  )
  start_process_subscriptions
  await_contention_evidence
end

Then("the Task race has deterministic execution evidence") do
  evidence = @contention_evidence.sole
  assert_acceptance_equal(task_command_id(@current_task_id), evidence.fetch(:command_id), "Task command")
  assert_acceptance_equal(@current_task_id, evidence.fetch(:task_id), "Task identity")
  assert_acceptance(evidence.fetch(:thread_id), "Task worker thread evidence is missing")
end

When("an independent MCP client requests cancellation before the worker resumes") do
  prepare_mcp_clients("task-canceller")
  @cancel_response = task_request(
    "tasks/cancel",
    @current_task_id,
    client_id: "task-canceller"
  )
end

When("the durable execution boundary is released") do
  release_contention_barrier
end

Then("the Task eventually has exactly one terminal state") do
  state = await_task_terminal(@current_task_id)
  terminal_events = task_events(@current_task_id).select do |event|
    %w[CoordinationTaskCompleted CoordinationTaskFailed CoordinationTaskCancelled].include?(event.type)
  end

  assert_acceptance_equal(1, terminal_events.length, "Terminal Task facts")
  assert_acceptance_equal(
    terminal_events.sole.type.delete_prefix("CoordinationTask").downcase,
    state.dig("result", "status"),
    "Persisted and public terminal state"
  )
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
    task_events_for_request(
      @current_arguments.fetch(:command_id),
      actor: @current_arguments.fetch(:actor)
    ),
    "Rejected Task submissions"
  )
  assert_acceptance_equal([], command_events(@current_arguments.fetch(:command_id)), "Command facts")
  assert_no_current_target_facts
end


def assert_semantic_task_completion(task_id, kind:)
  completion = task_events(task_id).find { _1.type == "CoordinationTaskCompleted" }
  assert_acceptance(completion, "Task #{task_id} has no completion fact")
  assert_acceptance_equal(3, completion.metadata.fetch("schema_version"), "Task completion schema")
  assert_acceptance_equal({ "task_id" => task_id }, completion.data, "Lean Task terminal payload")
  terminal = command_terminal_event(task_command_id(task_id))
  assert_acceptance(terminal, "Task #{task_id} has no terminal command fact")
  expected_type = kind == "success" ? "CommandSucceeded" : "CommandRejected"
  assert_acceptance_equal(expected_type, terminal.type, "Semantic command outcome")
  forbidden = %w[content structured_content structuredContent is_error isError]
  assert_acceptance_equal(
    [],
    completion.data.keys & forbidden,
    "Persisted MCP wire fields"
  )
end
