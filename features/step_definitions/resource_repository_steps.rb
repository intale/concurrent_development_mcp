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

def resource_identity_events(resource_id)
  event_store.read(
    streams.resource(resource_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: %w[ResourceRegistered ResourceBound],
      maximum_count: 2,
      direction: :asc
    )
  )
end
