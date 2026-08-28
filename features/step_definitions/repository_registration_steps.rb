# frozen_string_literal: true

When("the agent registers a caller-created Repository for scope {string}") do |scope|
  @repository_id = SecureRandom.uuid_v7
  @repository_arguments = {
    command_id: "cmd-cuc-repository-register",
    actor: { kind: "agent", id: "repository-agent" },
    repository_id: @repository_id,
    scope:,
    repository_key: "payments",
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
  scope_markers = event.markers.grep(/\Acompound:(?:repository-scope|scoped-repository|scoped-repository-key):v1:/)
  assert_acceptance_equal(3, scope_markers.length, "Scope markers")
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
      repository_key: "payments",
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
  await_read_model("Repository #{@repository_id} to become discoverable") do
    payload = call_tool(
      "repository_list",
      {
        scope: @repository_arguments.fetch(:scope),
        repository_key: @repository_arguments.fetch(:repository_key)
      }
    )
      .dig("result", "structuredContent")
    items = payload.dig("data", "page", "items") || []
    [ items.any? { _1.fetch("repository_id") == @repository_id }, payload ]
  end
end

When("two clean agents independently list Repositories using only that scope") do
  prepare_mcp_clients("repository-agent-a", "repository-agent-b")
  @repository_discovery_responses = %w[repository-agent-a repository-agent-b].map do |client_id|
    call_tool(
      "repository_list",
      {
        scope: @repository_arguments.fetch(:scope),
        repository_key: @repository_arguments.fetch(:repository_key)
      },
      client_id:
    )
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

Given(
  "independent agents {string} and {string} know only the same project scope and repository key"
) do |first_agent, second_agent|
  @repository_race_scope = "project:audit2/repository-bootstrap"
  @repository_race_key = "shared-project"
  @repository_race_agents = [ first_agent, second_agent ]
  prepare_mcp_clients(*@repository_race_agents)
  command_ids = repository_distinct_lane_command_ids("audit2.repository-register")
  @repository_race_requests = @repository_race_agents.each_with_index.map do |agent_id, index|
    {
      client_id: agent_id,
      command_id: command_ids.fetch(index),
      actor: { kind: "agent", id: agent_id },
      repository_id: SecureRandom.uuid_v7,
      scope: @repository_race_scope,
      repository_key: @repository_race_key,
      display_name: "Shared Project",
      paths: [ "/caller-visible/shared-project" ],
      remotes: [ "https://example.test/shared-project.git" ]
    }
  end
  install_contention_barrier(
    operation: "repository_register_dcb",
    command_ids: @repository_race_requests.map { _1.fetch(:command_id) }
  )
end

When("both registrations reach the deterministic database barrier with different proposed UUIDs") do
  proposed_ids = @repository_race_requests.map { _1.fetch(:repository_id) }
  assert_acceptance_equal(2, proposed_ids.uniq.length, "Distinct proposed Repository UUIDs")
  @repository_race_tasks = @repository_race_requests.map do |request|
    response = call_tool(
      "repository_register",
      request.except(:client_id),
      client_id: request.fetch(:client_id)
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "repository_register did not return a Task: #{response.inspect}")
    request.merge(task_id:)
  end
  start_process_subscriptions
  await_contention_evidence
  assert_acceptance_equal(2, @contention_evidence.map { _1.fetch(:thread_id) }.uniq.length, "Worker threads")
  assert_acceptance_equal([ 0, 1 ], @contention_evidence.map { _1.fetch(:worker_lane) }.sort, "Worker lanes")
end

When("the barrier releases both registrations") do
  release_contention_barrier
  @repository_race_states = @repository_race_tasks.map do |request|
    await_task_terminal(request.fetch(:task_id), client_id: request.fetch(:client_id))
  end
end

Then("one canonical Repository UUID is authoritative for that scope and key") do
  results = @repository_race_states.map { _1.dig("result", "result") }
  results.each do |result|
    assert_acceptance_equal(false, result.fetch("isError"), "Repository registration result")
  end
  canonical_ids = results.map { _1.dig("structuredContent", "data", "repository_id") }
  @repository_race_canonical_id = canonical_ids.uniq.sole

  marker = Coordinator::Shared::CompoundMarkerBuilder.new.call(
    Coordinator::Shared::CompoundMarkerDefinitionV1.new(
      purpose: "scoped-repository-key",
      components: [
        "scope:#{@repository_race_scope}",
        "repository-key:#{@repository_race_key}"
      ]
    )
  ).marker
  facts = event_store.read_global_marked(
    Coordinator::Write::GlobalMarkedEventReadCriteria.new(
      stream_context: "DevelopmentPlanning",
      stream_name: "Repository",
      event_types: [ "RepositoryRegistered" ],
      markers: [ marker ],
      maximum_count: 1,
      direction: :asc
    )
  )
  assert_acceptance_equal(1, facts.length, "Canonical Repository facts")
  assert_acceptance_equal(@repository_race_canonical_id, facts.sole.stream.stream_id, "Canonical stream")
end

Then("both agents discover the same canonical Repository through MCP") do
  await_read_model("canonical Repository to reach available discovery") do
    payload = call_tool(
      "repository_list",
      { scope: @repository_race_scope, repository_key: @repository_race_key },
      client_id: @repository_race_agents.first
    ).dig("result", "structuredContent")
    items = payload.dig("data", "page", "items") || []
    [ items.any? { _1.fetch("repository_id") == @repository_race_canonical_id }, payload ]
  end
  @repository_race_discovery = @repository_race_agents.map do |agent_id|
    call_tool(
      "repository_list",
      { scope: @repository_race_scope, repository_key: @repository_race_key },
      client_id: agent_id
    ).dig("result", "structuredContent")
  end
  assert_acceptance_equal(
    @repository_race_discovery.first,
    @repository_race_discovery.last,
    "Independent exact-key discovery"
  )
  assert_acceptance_equal(
    [ @repository_race_canonical_id ],
    @repository_race_discovery.first.dig("data", "page", "items").map { _1.fetch("repository_id") },
    "Discovered canonical Repository"
  )
end

When("both agents use the discovered Repository to contend for one file") do
  @repository_race_lease_outcomes = contend_for_shared_repository_file(@repository_race_canonical_id)
end

Then("the second lease is blocked in the shared Repository namespace") do
  first, second = @repository_race_lease_outcomes
  assert_acceptance_equal("ok", first.fetch("status"), "First lease result")
  assert_acceptance_equal("busy", second.fetch("status"), "Second lease result")
  assert_acceptance_equal(
    "agent-a",
    second.dig("data", "details", "owner_agent_id"),
    "Shared namespace owner"
  )
end

Given("an MCP result contains one or more next actions") do
  task_id = submit_and_execute(
    "guidance_record",
    command_id: "audit2.next-action.guidance",
    actor: { kind: "agent", id: "next-action-agent" },
    message_id: "MSG-AUD2-NEXT-ACTION",
    conversation_id: "CONV-AUD2-NEXT-ACTION",
    source: "mcp_client",
    text: "Validate advertised actions against live MCP discovery.",
    anchors: {
      repository_ids: [],
      change_set_id: nil,
      work_item_id: nil,
      attempt_id: nil
    }
  )
  state = task_request("tasks/get", task_id)
  @advertised_next_actions = state.dig(
    "result", "result", "structuredContent", "next_actions"
  )
  assert_acceptance(@advertised_next_actions.any?, "Expected at least one advertised next action")
end

When("an agent validates each action against current tool discovery") do
  tools = mcp_request(method: "tools/list", params: {}).dig("result", "tools")
  @discovered_tools_by_name = tools.to_h { [ _1.fetch("name"), _1 ] }
  @next_action_validation_errors = @advertised_next_actions.filter_map do |action|
    tool = @discovered_tools_by_name[action.fetch("tool")]
    next "Unknown tool #{action.fetch("tool")}" unless tool

    begin
      ::MCP::Tool::InputSchema.new(tool.fetch("inputSchema"))
        .validate_arguments(action.fetch("arguments"))
      nil
    rescue StandardError => error
      "#{action.fetch("tool")}: #{error.message}"
    end
  end
end

Then("every action is complete and schema-valid for its target tool") do
  assert_acceptance_equal([], @next_action_validation_errors, "Next-action validation errors")
end

Then("no mutation action contains placeholders or omitted required intent") do
  mutation_actions = @advertised_next_actions.select do |action|
    @discovered_tools_by_name.fetch(action.fetch("tool"))
      .fetch("annotations", {})
      .fetch("readOnlyHint", false) == false
  end
  assert_acceptance_equal([], mutation_actions, "Advertised mutation actions")
  serialized = JSON.generate(@advertised_next_actions)
  assert_acceptance(!/(?:TODO|placeholder|<[^>]+>)/i.match?(serialized), "Placeholder-free actions")
end

Given("an agent inspects current MCP discovery") do
  @actor_discovery = mcp_request(method: "tools/list", params: {}).dig("result", "tools")
  @server_discovery = mcp_request(method: "server/discover", params: {}).fetch("result")
end

When("the agent reads a mutation actor schema and description") do
  @mutation_actor_contracts = @actor_discovery.filter_map do |tool|
    next if tool.fetch("annotations", {}).fetch("readOnlyHint", false)

    actor = tool.dig("inputSchema", "properties", "actor")
    [ tool.fetch("name"), tool.fetch("description"), actor ] if actor
  end
end

Then("the contract does not claim that a supplied actor label proves identity") do
  assert_acceptance(@mutation_actor_contracts.any?, "Expected mutation actor contracts")
  @mutation_actor_contracts.each do |name, description, actor|
    assert_acceptance_equal(
      %w[id kind],
      actor.fetch("properties").keys.sort,
      "#{name} actor fields"
    )
    actor_description = actor.fetch("description")
    assert_acceptance(
      actor_description.include?("Caller-supplied attribution label"),
      "#{name} actor attribution description"
    )
    combined = "#{description} #{actor_description}".downcase
    assert_acceptance(!combined.include?("proves identity"), "#{name} must not claim proved identity")
    assert_acceptance(combined.include?("not authenticated"), "#{name} must disclaim authentication")
  end
end

Then("no authentication or session capability is implied") do
  capability_names = @server_discovery.fetch("capabilities").keys
  assert_acceptance(
    capability_names.none? { /auth|identity|session/i.match?(_1) },
    "No authentication/session capability"
  )
end
