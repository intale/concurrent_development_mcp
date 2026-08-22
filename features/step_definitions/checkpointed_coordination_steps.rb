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

Given(
  "agents {string} and {string} have active Attempts in ChangeSet {string}"
) do |first_agent_id, second_agent_id, change_set_id|
  @lease_change_set_id = change_set_id
  @lease_participants = [
    {
      agent_id: first_agent_id,
      work_item_id: "W-CUC-LSE-A",
      attempt_id: "A-CUC-LSE-A",
      unique_path: "app/models/alpha.rb"
    },
    {
      agent_id: second_agent_id,
      work_item_id: "W-CUC-LSE-B",
      attempt_id: "A-CUC-LSE-B",
      unique_path: "app/models/beta.rb"
    }
  ]

  submit_and_execute(
    "change_set_create",
    command_id: "cmd-cuc-lse-create",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    goal: "Coordinate overlapping file work",
    acceptance_criteria: [ "No two active agents own the same file" ]
  )
  @lease_participants.each do |participant|
    submit_and_execute(
      "work_item_create",
      command_id: "cmd-cuc-lse-create-#{participant.fetch(:work_item_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id: participant.fetch(:work_item_id),
      repository_id: "billing",
      goal: "Implement #{participant.fetch(:work_item_id)}",
      acceptance_criteria: [ "The work is verifiable" ]
    )
  end
  submit_and_execute(
    "change_set_activate",
    command_id: "cmd-cuc-lse-activate",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:
  )
  activation = change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
  Coordinator::Container["process_managers.change_set_readiness"].call(activation)

  @lease_participants.each do |participant|
    submit_and_execute(
      "work_item_acquire",
      command_id: "cmd-cuc-lse-acquire-#{participant.fetch(:attempt_id)}",
      actor: { kind: "agent", id: participant.fetch(:agent_id) },
      change_set_id:,
      work_item_id: participant.fetch(:work_item_id),
      attempt_id: participant.fetch(:attempt_id),
      base_snapshots: [
        { repository_id: "billing", commit_oid: "a" * 40 }
      ]
    )
  end
end

When(
  "both agents concurrently reserve initial write sets overlapping on {string}"
) do |shared_path|
  @shared_lease_path = shared_path
  @reservation_tasks = @lease_participants.map.with_index do |participant, index|
    arguments = {
      command_id: "cmd-cuc-lse-reserve-#{index + 1}",
      actor: { kind: "agent", id: participant.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: participant.fetch(:work_item_id),
      attempt_id: participant.fetch(:attempt_id),
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [
        { kind: "file", path: participant.fetch(:unique_path) },
        { kind: "file", path: shared_path }
      ],
      lease_duration_seconds: 300
    }
    task_id = call_tool("write_set_reserve", arguments).dig("result", "taskId")
    participant.merge(task_id:, arguments:)
  end

  @reservation_tasks.map do |reservation|
    Thread.new { execute_task(reservation.fetch(:task_id)) }
  end.each(&:value)
  @reservation_tasks.each do |reservation|
    reservation[:state] = task_request("tasks/get", reservation.fetch(:task_id))
    reservation[:outcome] = reservation.dig(:state, "result", "result", "structuredContent")
  end
end

Then("one reservation Task succeeds and the other completes busy") do
  statuses = @reservation_tasks.map { _1.dig(:outcome, "status") }
  assert_acceptance_equal([ "busy", "ok" ], statuses.sort, "Reservation Task outcomes")
  assert_acceptance(
    @reservation_tasks.all? { _1.dig(:state, "result", "status") == "completed" },
    "Both reservation Tasks must terminate as completed"
  )

  @winning_reservation = @reservation_tasks.find { _1.dig(:outcome, "status") == "ok" }
  @losing_reservation = @reservation_tasks.find { _1.dig(:outcome, "status") == "busy" }
  busy_details = @losing_reservation.dig(:outcome, "data", "details")
  assert_acceptance_equal(
    @winning_reservation.fetch(:attempt_id),
    busy_details.fetch("owner_attempt_id"),
    "Persisted busy owner"
  )
  assert_acceptance_equal(1, busy_details.fetch("fencing_token"), "Winning fencing token")
end

Then("the winner owns its complete write set") do
  event = write_set_events(@winning_reservation.fetch(:attempt_id)).sole
  expected_paths = [ @winning_reservation.fetch(:unique_path), @shared_lease_path ].sort
  assert_acceptance_equal(
    expected_paths,
    event.data.fetch("resources").map { _1.fetch("resource_path") }.sort,
    "Winning write-set resources"
  )
  expected_paths.each do |path|
    assert_acceptance_equal(1, lease_events(path).length, "Lease facts for #{path}")
  end
end

Then("the loser owns no partial write set") do
  assert_acceptance_equal(
    [],
    write_set_events(@losing_reservation.fetch(:attempt_id)),
    "Losing Attempt write set"
  )
  assert_acceptance_equal(
    [],
    lease_events(@losing_reservation.fetch(:unique_path)),
    "Losing unique resource lease"
  )
  assert_acceptance_equal(
    [],
    command_events(@losing_reservation.dig(:arguments, :command_id)),
    "Losing command completion"
  )
end

When("the winning Attempt reservation reaches the read side") do
  project_attempt_context(
    change_set_id: @lease_change_set_id,
    work_item_id: @winning_reservation.fetch(:work_item_id),
    attempt_id: @winning_reservation.fetch(:attempt_id)
  )
  @winning_context = call_tool(
    "coord_context",
    { attempt_id: @winning_reservation.fetch(:attempt_id) }
  )
end

Then("available context exposes the observed lease evidence without a freshness claim") do
  payload = @winning_context.dig("result", "structuredContent")
  attempt = payload.dig("data", "context", "attempts").find do |candidate|
    candidate.fetch("attempt_id") == @winning_reservation.fetch(:attempt_id)
  end
  write_set = attempt.fetch("write_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Available context status")
  assert_acceptance(!payload.key?("projection_status"), "Context must not expose a projection gate")
  assert_acceptance_equal(
    [ @shared_lease_path, @winning_reservation.fetch(:unique_path) ].sort,
    write_set.fetch("resources").map { _1.fetch("resource_path") }.sort,
    "Projected resource evidence"
  )
  assert_acceptance(write_set.key?("expires_at"), "Projected write set must preserve expiry evidence")
  assert_acceptance(
    (write_set.keys & %w[active fresh pending]).empty?,
    "Projected write set must not claim freshness or current activity"
  )
end

Given(
  "agent {string} has reserved {string} for active Attempt {string} in ChangeSet {string}"
) do |agent_id, initial_path, attempt_id, change_set_id|
  @expansion_agent_id = agent_id
  @expansion_initial_path = initial_path
  @expansion_attempt_id = attempt_id
  @expansion_change_set_id = change_set_id
  @expansion_work_item_id = "W-CUC-EXPAND"

  submit_and_execute(
    "change_set_create",
    command_id: "cmd-cuc-expand-create",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    goal: "Coordinate write-set expansion",
    acceptance_criteria: [ "Expansion preserves the current deadline" ]
  )
  submit_and_execute(
    "work_item_create",
    command_id: "cmd-cuc-expand-work-item",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    work_item_id: @expansion_work_item_id,
    repository_id: "billing",
    goal: "Implement the expanded change",
    acceptance_criteria: [ "Both files are coordinated" ]
  )
  submit_and_execute(
    "change_set_activate",
    command_id: "cmd-cuc-expand-activate",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:
  )
  activation = change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
  Coordinator::Container["process_managers.change_set_readiness"].call(activation)
  submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-expand-acquire",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @expansion_work_item_id,
    attempt_id:,
    base_snapshots: [ { repository_id: "billing", commit_oid: "a" * 40 } ]
  )
  reservation_task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-expand-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @expansion_work_item_id,
    attempt_id:,
    repository_id: "billing",
    base_commit_oid: "a" * 40,
    resources: [ { kind: "file", path: initial_path } ],
    lease_duration_seconds: 300
  )
  @expansion_reservation = task_request("tasks/get", reservation_task_id).dig(
    "result", "result", "structuredContent", "data"
  )

  project_attempt_context(
    change_set_id:,
    work_item_id: @expansion_work_item_id,
    attempt_id:
  )
  @context_before_expansion = call_tool("coord_context", { attempt_id: })
end

When("the agent expands the current write set with {string}") do |additional_path|
  @expansion_additional_path = additional_path
  @expansion_command_id = "cmd-cuc-expand-add"
  @expansion_task_id = call_tool(
    "write_set_expand",
    {
      command_id: @expansion_command_id,
      actor: { kind: "agent", id: @expansion_agent_id },
      change_set_id: @expansion_change_set_id,
      work_item_id: @expansion_work_item_id,
      attempt_id: @expansion_attempt_id,
      lease_set_id: @expansion_reservation.fetch("lease_set_id"),
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path: additional_path } ]
    }
  ).dig("result", "taskId")
  execute_task(@expansion_task_id)
  @expansion_task_state = task_request("tasks/get", @expansion_task_id)
end

Then("the expansion Task succeeds without extending the lease deadline") do
  result = @expansion_task_state.dig("result", "result")
  data = result.fetch("structuredContent").fetch("data")

  assert_acceptance_equal("completed", @expansion_task_state.dig("result", "status"), "Expansion Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Expansion tool error flag")
  assert_acceptance_equal(
    @expansion_reservation.fetch("lease_set_id"),
    data.fetch("lease_set_id"),
    "Expansion lease-set identity"
  )
  assert_acceptance_equal(
    @expansion_reservation.fetch("expires_at"),
    data.fetch("expires_at"),
    "Expansion deadline"
  )
  assert_acceptance_equal(
    [ @expansion_additional_path ],
    data.fetch("added_resources").map { _1.fetch("resource_path") },
    "Expansion additions"
  )
end

Then("the previous context remains available before expansion projection") do
  lagging = call_tool("coord_context", { attempt_id: @expansion_attempt_id })
  before_payload = @context_before_expansion.dig("result", "structuredContent")
  lagging_payload = lagging.dig("result", "structuredContent")
  write_set = lagging_payload.dig("data", "context", "attempts", 0, "write_set")

  assert_acceptance_equal("ok", lagging_payload.fetch("status"), "Lagging context status")
  assert_acceptance_equal(
    before_payload.fetch("context_token"),
    lagging_payload.fetch("context_token"),
    "Lagging context token"
  )
  assert_acceptance_equal(
    [ @expansion_initial_path ],
    write_set.fetch("resources").map { _1.fetch("resource_path") },
    "Lagging write-set evidence"
  )
end

When("the write-set expansion reaches the read side") do
  expansion = write_set_expansion_events(@expansion_attempt_id).sole
  Coordinator::Container["projectors.coord_context_v1"].call(expansion)
  @expanded_context = call_tool("coord_context", { attempt_id: @expansion_attempt_id })
end

Then("available context exposes both observed files without a freshness claim") do
  payload = @expanded_context.dig("result", "structuredContent")
  write_set = payload.dig("data", "context", "attempts", 0, "write_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Expanded context status")
  assert_acceptance_equal(
    [ @expansion_initial_path, @expansion_additional_path ].sort,
    write_set.fetch("resources").map { _1.fetch("resource_path") }.sort,
    "Expanded projected resources"
  )
  assert_acceptance_equal(
    @expansion_reservation.fetch("expires_at"),
    write_set.fetch("expires_at"),
    "Projected expansion deadline"
  )
  assert_acceptance(write_set.key?("last_expanded_at"), "Projected expansion time is missing")
  assert_acceptance(
    (write_set.keys & %w[active fresh pending]).empty?,
    "Expanded projection must not claim freshness or activity"
  )
end

Given(
  "agent {string} has reserved {string} and {string} for renewable Attempt {string} in ChangeSet {string}"
) do |agent_id, first_path, second_path, attempt_id, change_set_id|
  @renewal_agent_id = agent_id
  @renewal_paths = [ first_path, second_path ]
  @renewal_attempt_id = attempt_id
  @renewal_change_set_id = change_set_id
  @renewal_work_item_id = "W-CUC-RENEW"

  submit_and_execute(
    "change_set_create",
    command_id: "cmd-cuc-renew-create",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    goal: "Coordinate complete lease-set renewal",
    acceptance_criteria: [ "Renewal preserves every lease identity" ]
  )
  submit_and_execute(
    "work_item_create",
    command_id: "cmd-cuc-renew-work-item",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    work_item_id: @renewal_work_item_id,
    repository_id: "billing",
    goal: "Implement the renewable change",
    acceptance_criteria: [ "Both files remain owned together" ]
  )
  submit_and_execute(
    "change_set_activate",
    command_id: "cmd-cuc-renew-activate",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:
  )
  activation = change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
  Coordinator::Container["process_managers.change_set_readiness"].call(activation)
  submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-renew-acquire",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @renewal_work_item_id,
    attempt_id:,
    base_snapshots: [ { repository_id: "billing", commit_oid: "a" * 40 } ]
  )
  reservation_task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-renew-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @renewal_work_item_id,
    attempt_id:,
    repository_id: "billing",
    base_commit_oid: "a" * 40,
    resources: @renewal_paths.map { { kind: "file", path: _1 } },
    lease_duration_seconds: 300
  )
  @renewal_reservation = task_request("tasks/get", reservation_task_id).dig(
    "result", "result", "structuredContent", "data"
  )

  project_attempt_context(
    change_set_id:,
    work_item_id: @renewal_work_item_id,
    attempt_id:
  )
  @context_before_renewal = call_tool("coord_context", { attempt_id: })
end

When("the agent renews the complete observed lease set") do
  @renewal_task_id = call_tool(
    "lease_renew",
    {
      command_id: "cmd-cuc-renew-set",
      actor: { kind: "agent", id: @renewal_agent_id },
      change_set_id: @renewal_change_set_id,
      work_item_id: @renewal_work_item_id,
      attempt_id: @renewal_attempt_id,
      lease_set_id: @renewal_reservation.fetch("lease_set_id"),
      leases: @renewal_reservation.fetch("resources").map do |reference|
        {
          resource_key_hash: reference.fetch("resource_key_hash"),
          lease_id: reference.fetch("lease_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end,
      lease_duration_seconds: 600
    }
  ).dig("result", "taskId")
  execute_task(@renewal_task_id)
  @renewal_task_state = task_request("tasks/get", @renewal_task_id)
end

Then("the renewal Task succeeds without changing lease identities or fencing tokens") do
  result = @renewal_task_state.dig("result", "result")
  data = result.fetch("structuredContent").fetch("data")
  before_refs = @renewal_reservation.fetch("resources").map do |reference|
    reference.values_at("resource_key_hash", "lease_id", "fencing_token")
  end
  after_refs = data.fetch("resources").map do |reference|
    reference.values_at("resource_key_hash", "lease_id", "fencing_token")
  end

  assert_acceptance_equal("completed", @renewal_task_state.dig("result", "status"), "Renewal Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Renewal tool error flag")
  assert_acceptance_equal(before_refs, after_refs, "Renewed lease references")
  assert_acceptance_equal(
    @renewal_reservation.fetch("expires_at"),
    data.fetch("previous_expires_at"),
    "Renewal previous deadline"
  )
  assert_acceptance(
    data.fetch("expires_at") > @renewal_reservation.fetch("expires_at"),
    "Renewal must move the deadline forward"
  )
  @renewal_result = data
end

Then("the previous context remains available before renewal projection") do
  lagging = call_tool("coord_context", { attempt_id: @renewal_attempt_id })
  before_payload = @context_before_renewal.dig("result", "structuredContent")
  lagging_payload = lagging.dig("result", "structuredContent")
  write_set = lagging_payload.dig("data", "context", "attempts", 0, "write_set")

  assert_acceptance_equal("ok", lagging_payload.fetch("status"), "Lagging renewal context status")
  assert_acceptance_equal(
    before_payload.fetch("context_token"),
    lagging_payload.fetch("context_token"),
    "Lagging renewal context token"
  )
  assert_acceptance_equal(
    @renewal_reservation.fetch("expires_at"),
    write_set.fetch("expires_at"),
    "Lagging observed deadline"
  )
  assert_acceptance(!lagging_payload.key?("projection_status"), "Lagging context must remain available")
end

When("the write-set renewal reaches the read side") do
  renewal = write_set_renewal_events(@renewal_attempt_id).sole
  Coordinator::Container["projectors.coord_context_v1"].call(renewal)
  @renewed_context = call_tool("coord_context", { attempt_id: @renewal_attempt_id })
end

Then("available context exposes the later observed deadline without a freshness claim") do
  payload = @renewed_context.dig("result", "structuredContent")
  write_set = payload.dig("data", "context", "attempts", 0, "write_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Renewed context status")
  assert_acceptance_equal(@renewal_result.fetch("expires_at"), write_set.fetch("expires_at"), "Observed deadline")
  assert_acceptance_equal(
    @renewal_reservation.fetch("expires_at"),
    write_set.fetch("previous_expires_at"),
    "Observed previous deadline"
  )
  assert_acceptance(write_set.key?("last_renewed_at"), "Projected renewal time is missing")
  assert_acceptance(
    (write_set.keys & %w[active fresh pending]).empty?,
    "Renewed projection must not claim freshness or activity"
  )
end

Given(
  "agent {string} has reserved {string} and {string} for releasable Attempt {string} in ChangeSet {string}"
) do |agent_id, first_path, second_path, attempt_id, change_set_id|
  @release_agent_id = agent_id
  @release_paths = [ first_path, second_path ]
  @release_attempt_id = attempt_id
  @release_change_set_id = change_set_id
  @release_work_item_id = "W-CUC-RELEASE"

  submit_and_execute(
    "change_set_create",
    command_id: "cmd-cuc-release-create",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    goal: "Coordinate complete lease-set release",
    acceptance_criteria: [ "Release preserves every lease identity" ]
  )
  submit_and_execute(
    "work_item_create",
    command_id: "cmd-cuc-release-work-item",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    work_item_id: @release_work_item_id,
    repository_id: "billing",
    goal: "Implement the releasable change",
    acceptance_criteria: [ "Both files are released together" ]
  )
  submit_and_execute(
    "change_set_activate",
    command_id: "cmd-cuc-release-activate",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:
  )
  activation = change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
  Coordinator::Container["process_managers.change_set_readiness"].call(activation)
  submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-release-acquire",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @release_work_item_id,
    attempt_id:,
    base_snapshots: [ { repository_id: "billing", commit_oid: "a" * 40 } ]
  )
  reservation_task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-release-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @release_work_item_id,
    attempt_id:,
    repository_id: "billing",
    base_commit_oid: "a" * 40,
    resources: @release_paths.map { { kind: "file", path: _1 } },
    lease_duration_seconds: 300
  )
  @release_reservation = task_request("tasks/get", reservation_task_id).dig(
    "result", "result", "structuredContent", "data"
  )

  project_attempt_context(
    change_set_id:,
    work_item_id: @release_work_item_id,
    attempt_id:
  )
  @context_before_release = call_tool("coord_context", { attempt_id: })
end

When("the agent releases the complete observed lease set") do
  @release_task_id = call_tool(
    "lease_release",
    {
      command_id: "cmd-cuc-release-set",
      actor: { kind: "agent", id: @release_agent_id },
      change_set_id: @release_change_set_id,
      work_item_id: @release_work_item_id,
      attempt_id: @release_attempt_id,
      lease_set_id: @release_reservation.fetch("lease_set_id"),
      leases: @release_reservation.fetch("resources").map do |reference|
        {
          resource_key_hash: reference.fetch("resource_key_hash"),
          lease_id: reference.fetch("lease_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end
    }
  ).dig("result", "taskId")
  execute_task(@release_task_id)
  @release_task_state = task_request("tasks/get", @release_task_id)
end

Then("the release Task succeeds without changing lease identities or fencing tokens") do
  result = @release_task_state.dig("result", "result")
  data = result.fetch("structuredContent").fetch("data")
  before_refs = @release_reservation.fetch("resources").map do |reference|
    reference.values_at("resource_key_hash", "lease_id", "fencing_token")
  end
  after_refs = data.fetch("resources").map do |reference|
    reference.values_at("resource_key_hash", "lease_id", "fencing_token")
  end

  assert_acceptance_equal("completed", @release_task_state.dig("result", "status"), "Release Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Release tool error flag")
  assert_acceptance_equal(before_refs, after_refs, "Released lease references")
  assert_acceptance_equal(
    @release_reservation.fetch("expires_at"),
    data.fetch("previous_expires_at"),
    "Release previous deadline"
  )
  assert_acceptance(data.fetch("released_at"), "Release timestamp is missing")
  assert_acceptance_equal(1, write_set_release_events(@release_attempt_id).length, "Write-set release facts")
  @release_result = data
end

Then("the previous context remains available before release projection") do
  lagging = call_tool("coord_context", { attempt_id: @release_attempt_id })
  before_payload = @context_before_release.dig("result", "structuredContent")
  lagging_payload = lagging.dig("result", "structuredContent")
  write_set = lagging_payload.dig("data", "context", "attempts", 0, "write_set")

  assert_acceptance_equal("ok", lagging_payload.fetch("status"), "Lagging release context status")
  assert_acceptance_equal(
    before_payload.fetch("context_token"),
    lagging_payload.fetch("context_token"),
    "Lagging release context token"
  )
  assert_acceptance_equal(nil, write_set.fetch("released_at"), "Lagging observed release")
  assert_acceptance_equal(
    @release_paths.sort,
    write_set.fetch("resources").map { _1.fetch("resource_path") }.sort,
    "Lagging release resources"
  )
  assert_acceptance(!lagging_payload.key?("projection_status"), "Lagging context must remain available")
end

When("the write-set release reaches the read side") do
  release = write_set_release_events(@release_attempt_id).sole
  Coordinator::Container["projectors.coord_context_v1"].call(release)
  @released_context = call_tool("coord_context", { attempt_id: @release_attempt_id })
end

Then("available context exposes the observed release without a freshness claim") do
  payload = @released_context.dig("result", "structuredContent")
  write_set = payload.dig("data", "context", "attempts", 0, "write_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Released context status")
  assert_acceptance_equal(@release_result.fetch("released_at"), write_set.fetch("released_at"), "Observed release")
  assert_acceptance_equal(
    @release_reservation.fetch("expires_at"),
    write_set.fetch("expires_at"),
    "Retained observed deadline"
  )
  assert_acceptance_equal(
    @release_paths.sort,
    write_set.fetch("resources").map { _1.fetch("resource_path") }.sort,
    "Retained released resources"
  )
  assert_acceptance(
    (write_set.keys & %w[active fresh pending]).empty?,
    "Released projection must not claim freshness or activity"
  )
end
