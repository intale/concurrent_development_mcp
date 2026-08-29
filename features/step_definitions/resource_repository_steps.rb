# frozen_string_literal: true

Given("a registered Repository is available for Resource resolution") do
  @resource_repository_id = acceptance_repository_id
end

Given("read-model subscriptions are stopped for Resource resolution") do
  stop_read_model_subscriptions
end

When("the agent resolves file {string} through MCP") do |path|
  @resource_path = path
  @resource_command_id = "cuc-resource-resolve-#{path.parameterize(separator: "-")}"
  @resource_task_id = submit_and_execute(
    "resource_resolve",
    command_id: @resource_command_id,
    actor: { kind: "agent", id: "resource-agent" },
    repository_id: @resource_repository_id,
    kind: "file",
    path:
  )
  @resource_task_state = task_request("tasks/get", @resource_task_id)
end

Then("the Resource Task returns a server-generated UUIDv7") do
  result = @resource_task_state.dig("result", "result")
  data = result.dig("structuredContent", "data")
  @resource_id = data.fetch("resource_id")

  assert_acceptance_equal("completed", @resource_task_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Resource resolution error")
  assert_acceptance(
    Coordinator::Shared::Types::UUID_V7_PATTERN.match?(@resource_id),
    "Resource ID is not UUIDv7: #{@resource_id.inspect}"
  )
  assert_acceptance_equal(@resource_path, data.fetch("normalized_path"), "Normalized path")
end

Then("one registration and binding pair is durable in that Resource stream") do
  events = resource_identity_events(@resource_id)
  assert_acceptance_equal(%w[ResourceRegistered ResourceBound], events.map(&:type), "Resource facts")
  assert_acceptance_equal([ 0, 1 ], events.map(&:stream_revision), "Resource revisions")
end

Then("Resource discovery eventually reports it as {string}") do |status|
  @resource_projection = await_read_model("Resource #{@resource_id} to project as #{status}") do
    payload = projected_resource(@resource_id)
    observed = payload.dig("data", "resource", "lifecycle_status")
    [ payload["status"] == "ok" && observed == status, payload ]
  end
end

When("read-model subscriptions are stopped after Resource discovery") do
  stop_read_model_subscriptions
end

Then("available Resource discovery still reports it as {string} without a freshness gate") do |status|
  payload = projected_resource(@resource_id)

  assert_acceptance_equal("ok", payload.fetch("status"), "Available Resource query status")
  assert_acceptance_equal(
    status,
    payload.dig("data", "resource", "lifecycle_status"),
    "Available stale Resource lifecycle"
  )
  assert_acceptance_equal([], payload.fetch("warnings"), "Freshness warnings")
end

When("read-model subscriptions restart for Resource discovery") do
  start_read_model_subscriptions
end

When("the agent resolves the same Resource tuple with another command") do
  task_id = submit_and_execute(
    "resource_resolve",
    command_id: "#{@resource_command_id}-again",
    actor: { kind: "agent", id: "resource-agent" },
    repository_id: @resource_repository_id,
    kind: "file",
    path: @resource_path
  )
  @second_resource_task_state = task_request("tasks/get", task_id)
end

Then("the second Resource Task returns the same UUID without another Resource fact") do
  result = @second_resource_task_state.dig("result", "result")
  data = result.dig("structuredContent", "data")

  assert_acceptance_equal(false, result.fetch("isError"), "Existing Resource error")
  assert_acceptance_equal(@resource_id, data.fetch("resource_id"), "Existing Resource ID")
  assert_acceptance_equal("existing", data.fetch("outcome"), "Existing outcome")
  assert_acceptance_equal(2, resource_identity_events(@resource_id).length, "Resource fact count")
end

When("two agents concurrently resolve file {string} through MCP") do |path|
  @resource_path = path
  agent_ids = %w[resource-agent-a resource-agent-b]
  prepare_mcp_clients(*agent_ids)
  command_ids = repository_distinct_lane_command_ids("cuc.resource-race")
  install_contention_barrier(operation: "resource_resolve_dcb", command_ids:)
  @resource_race_tasks = agent_ids.each_with_index.map do |agent_id, index|
    response = call_tool(
      "resource_resolve",
      {
        command_id: command_ids.fetch(index),
        actor: { kind: "agent", id: agent_id },
        repository_id: @resource_repository_id,
        kind: "file",
        path:
      },
      client_id: agent_id
    )
    { client_id: agent_id, task_id: response.dig("result", "taskId") }
  end
  start_process_subscriptions
  await_contention_evidence
  release_contention_barrier
  @resource_race_states = @resource_race_tasks.map do |task|
    await_task_terminal(task.fetch(:task_id), client_id: task.fetch(:client_id))
  end
end

Then("both Resource Tasks succeed with one canonical UUID") do
  results = @resource_race_states.map { _1.dig("result", "result") }
  results.each { assert_acceptance_equal(false, _1.fetch("isError"), "Contended result") }
  @resource_id = results.map { _1.dig("structuredContent", "data", "resource_id") }.uniq.sole
end

Then("exactly one registration and binding pair exists for the contended tuple") do
  assert_acceptance_equal(
    %w[ResourceRegistered ResourceBound],
    resource_identity_events(@resource_id).map(&:type),
    "Contended Resource facts"
  )
end

When("the agent removes the current Resource because it was {string}") do |reason|
  @resource_unbinding_count_before = resource_identity_events(@resource_id).count do
    _1.type == "ResourceUnbound"
  end
  @resource_removal_state = execute_resource_removal(
    command_suffix: "remove",
    reason:
  )
end

When("the agent repeats the Resource removal because it was {string}") do |reason|
  @resource_unbinding_count_before = resource_identity_events(@resource_id).count do
    _1.type == "ResourceUnbound"
  end
  @resource_removal_state = execute_resource_removal(
    command_suffix: "remove-again",
    reason:
  )
end

Then("the Resource removal reports {string} with one unbinding fact") do |outcome|
  result = @resource_removal_state.dig("result", "result")
  data = result.dig("structuredContent", "data")

  assert_acceptance_equal(false, result.fetch("isError"), "Resource removal error")
  assert_acceptance_equal(outcome, data.fetch("outcome"), "Resource removal outcome")
  assert_acceptance_equal(
    @resource_unbinding_count_before + 1,
    resource_identity_events(@resource_id).count { _1.type == "ResourceUnbound" },
    "Resource unbinding count"
  )
end

Then("the Resource removal reports {string} without another unbinding fact") do |outcome|
  result = @resource_removal_state.dig("result", "result")
  data = result.dig("structuredContent", "data")

  assert_acceptance_equal(false, result.fetch("isError"), "Repeated removal error")
  assert_acceptance_equal(outcome, data.fetch("outcome"), "Repeated removal outcome")
  assert_acceptance_equal(
    @resource_unbinding_count_before,
    resource_identity_events(@resource_id).count { _1.type == "ResourceUnbound" },
    "Repeated Resource unbinding count"
  )
end

When("the agent resolves the inactive Resource tuple again") do
  @reactivated_resource_state = execute_resource_resolution(
    command_suffix: "reactivate",
    kind: "file",
    path: @resource_path
  )
end

Then("the Resource is reactivated with its original UUID and no new registration") do
  result = @reactivated_resource_state.dig("result", "result")
  data = result.dig("structuredContent", "data")
  events = resource_identity_events(@resource_id)

  assert_acceptance_equal(false, result.fetch("isError"), "Resource reactivation error")
  assert_acceptance_equal(@resource_id, data.fetch("resource_id"), "Reactivated Resource ID")
  assert_acceptance_equal("reactivated", data.fetch("outcome"), "Reactivation outcome")
  assert_acceptance_equal(1, events.count { _1.type == "ResourceRegistered" }, "Registration count")
  assert_acceptance_equal(2, events.count { _1.type == "ResourceBound" }, "Binding count")
end

When("the agent resolves renamed file {string} through MCP") do |path|
  @previous_resource_id = @resource_id
  @resource_path = path
  @renamed_resource_state = execute_resource_resolution(
    command_suffix: "renamed",
    kind: "file",
    path:
  )
end

Then("the renamed tuple has a distinct current UUID") do
  result = @renamed_resource_state.dig("result", "result")
  data = result.dig("structuredContent", "data")

  assert_acceptance_equal(false, result.fetch("isError"), "Renamed Resource resolution error")
  assert_acceptance(data.fetch("resource_id") != @previous_resource_id, "Rename reused the old tuple UUID")
  assert_acceptance_equal("registered", data.fetch("outcome"), "Renamed Resource outcome")
end

When("the agent tries to resolve directory {string} through MCP") do |path|
  @kind_conflict_state = execute_resource_resolution(
    command_suffix: "kind-conflict",
    kind: "directory",
    path:
  )
end

Then("Resource resolution is denied by the current kind") do
  result = @kind_conflict_state.dig("result", "result")

  assert_acceptance_equal(true, result.fetch("isError"), "Kind conflict error flag")
  assert_acceptance_equal(
    "resource_path_conflict",
    result.dig("structuredContent", "data", "code"),
    "Kind conflict code"
  )
end

When("the agent resolves directory {string} after removal") do |path|
  @previous_resource_id = @resource_id
  @new_kind_resource_state = execute_resource_resolution(
    command_suffix: "kind-changed",
    kind: "directory",
    path:
  )
end

Then("the new kind has a distinct current UUID") do
  result = @new_kind_resource_state.dig("result", "result")
  data = result.dig("structuredContent", "data")

  assert_acceptance_equal(false, result.fetch("isError"), "Kind-change Resource resolution error")
  assert_acceptance(data.fetch("resource_id") != @previous_resource_id, "Kind change reused the old tuple UUID")
  assert_acceptance_equal("directory", data.fetch("kind"), "Kind-change Resource kind")
  assert_acceptance_equal("registered", data.fetch("outcome"), "Kind-change Resource outcome")
end

def execute_resource_removal(command_suffix:, reason:)
  task_id = submit_and_execute(
    "resource_remove",
    command_id: "#{@resource_command_id}-#{command_suffix}",
    actor: { kind: "agent", id: "resource-agent" },
    resource_id: @resource_id,
    reason:
  )
  task_request("tasks/get", task_id)
end

def execute_resource_resolution(command_suffix:, kind:, path:)
  task_id = submit_and_execute(
    "resource_resolve",
    command_id: "#{@resource_command_id}-#{command_suffix}",
    actor: { kind: "agent", id: "resource-agent" },
    repository_id: @resource_repository_id,
    kind:,
    path:
  )
  task_request("tasks/get", task_id)
end

def resource_identity_events(resource_id)
  event_store.read(
    streams.resource(resource_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: %w[ResourceRegistered ResourceBound ResourceUnbound],
      maximum_count: 16,
      direction: :asc
    )
  )
end

def projected_resource(resource_id)
  call_tool("resource_get", { resource_id: })
    .dig("result", "structuredContent")
end
