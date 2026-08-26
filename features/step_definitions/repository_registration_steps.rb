# frozen_string_literal: true

When("the agent registers a caller-created Repository for scope {string}") do |scope|
  @repository_id = SecureRandom.uuid_v7
  @repository_arguments = {
    command_id: "cmd-cuc-repository-register",
    actor: { kind: "agent", id: "repository-agent" },
    repository_id: @repository_id,
    scope:,
    display_name: "Payments API",
    paths: [ "/client-visible/workspaces/payments" ],
    remotes: [ "https://example.test/payments.git" ]
  }
  @repository_task_id = submit_and_execute("repository_register", **@repository_arguments)
  @repository_task_state = task_request("tasks/get", @repository_task_id)
end

Given("a caller-created Repository is registered for scope {string}") do |scope|
  step(%(the agent registers a caller-created Repository for scope "#{scope}"))
  @original_repository_result = @repository_task_state.dig("result", "result")
end

Then("the Repository Task completes with the exact attributed metadata") do
  result = @repository_task_state.dig("result", "result")
  data = result.dig("structuredContent", "data")

  assert_acceptance_equal("completed", @repository_task_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Tool error flag")
  assert_acceptance_equal(@repository_id, data.fetch("repository_id"), "Repository identity")
  assert_acceptance_equal(@repository_arguments.fetch(:scope), data.fetch("scope"), "Repository scope")
  assert_acceptance_equal(@repository_arguments.fetch(:paths), data.fetch("paths"), "Attributed paths")
  assert_acceptance_equal(@repository_arguments.fetch(:remotes), data.fetch("remotes"), "Attributed remotes")
end

Then("one scoped Repository fact is durable without a server-derived location") do
  events = event_store.read(
    streams.repository(@repository_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "RepositoryRegistered" ],
      maximum_count: 1,
      direction: :asc
    )
  )
  event = events.sole

  assert_acceptance_equal(@repository_arguments.fetch(:scope), event.data.fetch("scope"), "Persisted scope")
  assert_acceptance_equal(@repository_arguments.fetch(:paths), event.data.fetch("paths"), "Persisted paths")
  scope_markers = event.markers.grep(/\Acompound:(?:repository-scope|scoped-repository):v1:/)
  assert_acceptance_equal(2, scope_markers.length, "Scope markers")
end

When("the agent tries to register Repository identity {string}") do |repository_id|
  @invalid_repository_command_id = "cmd-cuc-repository-invalid"
  @invalid_repository_response = call_tool(
    "repository_register",
    {
      command_id: @invalid_repository_command_id,
      actor: { kind: "agent", id: "repository-agent" },
      repository_id:,
      scope: "project:payments/workspace:primary",
      display_name: "Payments API",
      paths: [],
      remotes: []
    }
  )
end

Then("registration is rejected before a Task or coordination fact exists") do
  result = @invalid_repository_response.fetch("result")

  assert_acceptance_equal("complete", result.fetch("resultType"), "Immediate result type")
  assert_acceptance_equal(true, result.fetch("isError"), "Tool error flag")
  assert_acceptance_equal([], task_events_for_command(@invalid_repository_command_id), "Task facts")
  assert_acceptance_equal([], command_events(@invalid_repository_command_id), "Command facts")
end

When("the agent retries the exact Repository command") do
  @repository_retry_task_id = submit_and_execute("repository_register", **@repository_arguments)
  @repository_retry_state = task_request("tasks/get", @repository_retry_task_id)
end

Then("the retry exposes the original result without another Repository fact") do
  retry_result = @repository_retry_state.dig("result", "result")
  events = event_store.read(
    streams.repository(@repository_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "RepositoryRegistered" ],
      maximum_count: 2,
      direction: :asc
    )
  )

  assert_acceptance(@repository_retry_task_id != @repository_task_id, "Retry must have its own Task")
  assert_acceptance_equal(@original_repository_result, retry_result, "Replay result")
  assert_acceptance_equal(1, events.length, "Repository facts")
  assert_acceptance_equal(1, command_events(@repository_arguments.fetch(:command_id)).length, "Command facts")
end

When("the agent tries to bind that Repository identity to scope {string}") do |scope|
  @repository_conflict_command_id = "cmd-cuc-repository-conflict"
  @repository_conflict_task_id = submit_and_execute(
    "repository_register",
    **@repository_arguments.merge(command_id: @repository_conflict_command_id, scope:)
  )
  @repository_conflict_state = task_request("tasks/get", @repository_conflict_task_id)
end

Then("the conflicting Task completes with Repository identity conflict") do
  result = @repository_conflict_state.dig("result", "result")
  content = result.fetch("structuredContent")

  assert_acceptance_equal("completed", @repository_conflict_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(true, result.fetch("isError"), "Tool error flag")
  assert_acceptance_equal("conflict", content.fetch("status"), "Conflict status")
  assert_acceptance_equal("repository_identity_conflict", content.dig("data", "code"), "Conflict code")
end

Then("the rejected command writes no command fact") do
  assert_acceptance_equal([], command_events(@repository_conflict_command_id), "Rejected command facts")
end

Given("the Repository registration reaches scoped discovery") do
  event = event_store.read(
    streams.repository(@repository_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "RepositoryRegistered" ],
      maximum_count: 1,
      direction: :asc
    )
  ).sole
  Coordinator::Container["projectors.repositories_v1"].call(event)
end

When("two clean agents independently list Repositories using only that scope") do
  @repository_discovery_responses = 2.times.map do
    @mcp_session = nil
    @request_id = 0
    call_tool("repository_list", { scope: @repository_arguments.fetch(:scope) })
      .dig("result", "structuredContent")
  end
end

Then("both agents discover the same canonical Repository and attributed metadata") do
  first, second = @repository_discovery_responses
  assert_acceptance_equal(first, second, "Independent Repository discovery")
  item = first.dig("data", "page", "items").sole
  assert_acceptance_equal(@repository_id, item.fetch("repository_id"), "Canonical Repository identity")
  assert_acceptance_equal(@repository_arguments.fetch(:scope), item.fetch("scope"), "Exact scope")
  assert_acceptance_equal(@repository_arguments.fetch(:paths), item.fetch("paths"), "Attributed paths")
  assert_acceptance_equal(@repository_arguments.fetch(:remotes), item.fetch("remotes"), "Attributed remotes")
end

Then("Repository discovery stays available without a freshness contract") do
  @repository_discovery_responses.each do |payload|
    serialized = JSON.generate(payload)
    assert_acceptance_equal("ok", payload.fetch("status"), "Repository discovery status")
    assert_acceptance(
      %w[fresh pending projection_status].none? { serialized.include?(_1) },
      "Repository discovery must not expose a freshness gate"
    )
  end
end
