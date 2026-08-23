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

When(
  "agent {string} reserves {string} for {int} seconds at {string}"
) do |agent_id, path, duration, started_at|
  @expiry_predecessor = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  assert_acceptance(@expiry_predecessor, "Unknown predecessor agent #{agent_id}")

  @expiry_path = path
  @expiry_started_at = Time.iso8601(started_at)
  @expiry_predecessor_command_id = "cmd-cuc-expiry-predecessor"
  @expiry_predecessor_task_id = Timecop.freeze(@expiry_started_at) do
    task_id = call_tool(
      "write_set_reserve",
      {
        command_id: @expiry_predecessor_command_id,
        actor: { kind: "agent", id: agent_id },
        change_set_id: @lease_change_set_id,
        work_item_id: @expiry_predecessor.fetch(:work_item_id),
        attempt_id: @expiry_predecessor.fetch(:attempt_id),
        repository_id: "billing",
        base_commit_oid: "a" * 40,
        resources: [ { kind: "file", path: } ],
        lease_duration_seconds: duration
      }
    ).dig("result", "taskId")
    execute_task(task_id)
    task_id
  end
  @expiry_predecessor_state = task_request("tasks/get", @expiry_predecessor_task_id)
  @expiry_predecessor_result = @expiry_predecessor_state.dig(
    "result", "result", "structuredContent", "data"
  )
  @expiry_source = lease_events(path).sole
end

When("that reservation reaches the available read side") do
  project_attempt_context(
    change_set_id: @lease_change_set_id,
    work_item_id: @expiry_predecessor.fetch(:work_item_id),
    attempt_id: @expiry_predecessor.fetch(:attempt_id)
  )
  @expiry_predecessor_context = call_tool(
    "coord_context",
    { attempt_id: @expiry_predecessor.fetch(:attempt_id) }
  )
end

When(
  "after its deadline agent {string} reserves the same file before the expiry policy runs"
) do |agent_id|
  @expiry_successor = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  assert_acceptance(@expiry_successor, "Unknown successor agent #{agent_id}")

  @expiry_successor_task_id = Timecop.freeze(@expiry_started_at + 31) do
    task_id = call_tool(
      "write_set_reserve",
      {
        command_id: "cmd-cuc-expiry-successor",
        actor: { kind: "agent", id: agent_id },
        change_set_id: @lease_change_set_id,
        work_item_id: @expiry_successor.fetch(:work_item_id),
        attempt_id: @expiry_successor.fetch(:attempt_id),
        repository_id: "billing",
        base_commit_oid: "a" * 40,
        resources: [ { kind: "file", path: @expiry_path } ],
        lease_duration_seconds: 300
      }
    ).dig("result", "taskId")
    execute_task(task_id)
    task_id
  end
  @expiry_successor_state = task_request("tasks/get", @expiry_successor_task_id)
  @expiry_successor_result = @expiry_successor_state.dig(
    "result", "result", "structuredContent", "data"
  )
end

Then("the successor reservation Task succeeds with the next fencing token") do
  result = @expiry_successor_state.dig("result", "result")
  reference = @expiry_successor_result.fetch("resources").sole

  assert_acceptance_equal("completed", @expiry_successor_state.dig("result", "status"), "Successor Task")
  assert_acceptance_equal(false, result.fetch("isError"), "Successor tool error flag")
  assert_acceptance_equal(2, reference.fetch("fencing_token"), "Successor fencing token")
  assert_acceptance_equal(@expiry_path, reference.fetch("resource_path"), "Successor resource")
end

Then("the successor was admitted without an expiry audit fact") do
  events = lease_events(@expiry_path)

  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseAcquired" ],
    events.map(&:type),
    "Lease lifecycle before the old timer"
  )
  assert_acceptance_equal([ 1, 2 ], events.map { _1.data.fetch("fencing_token") }, "Fencing history")
end

When("the expired predecessor timer is handled") do
  source = Coordinator::Container["lease_expiry_source_builder"].call(@expiry_source)
  locator = Coordinator::Processes::LeaseExpirySourceLocatorV1.from_source(source)
  @expiry_policy_result = Timecop.freeze(@expiry_started_at + 32) do
    Coordinator::Container["lease_expiry_policy"].call(locator)
  end
end

Then("the timer is superseded and cannot affect the successor") do
  assert_acceptance(@expiry_policy_result.success?, "The old timer policy failed unexpectedly")
  assert_acceptance_equal(
    "lease_observation_superseded",
    @expiry_policy_result.value!.outcome,
    "Old timer outcome"
  )
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseAcquired" ],
    lease_events(@expiry_path).map(&:type),
    "Lease lifecycle after the old timer"
  )
  assert_acceptance_equal(
    [],
    command_events(@expiry_source.id),
    "Superseded expiry command completion"
  )
end

Then("the predecessor's older context remains available without a freshness claim") do
  current = call_tool(
    "coord_context",
    { attempt_id: @expiry_predecessor.fetch(:attempt_id) }
  )
  previous_payload = @expiry_predecessor_context.dig("result", "structuredContent")
  payload = current.dig("result", "structuredContent")
  write_set = payload.dig("data", "context", "attempts", 0, "write_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Elapsed predecessor context status")
  assert_acceptance_equal(previous_payload.fetch("context_token"), payload.fetch("context_token"), "Context token")
  assert_acceptance_equal(@expiry_path, write_set.fetch("resources").sole.fetch("resource_path"), "Observed file")
  assert_acceptance_equal(
    @expiry_predecessor_result.fetch("expires_at"),
    write_set.fetch("expires_at"),
    "Observed predecessor deadline"
  )
  assert_acceptance(
    (write_set.keys & %w[active fresh pending]).empty?,
    "Elapsed projection must not claim freshness or activity"
  )
  assert_acceptance(!payload.key?("projection_status"), "Elapsed context must not expose a projection gate")
end

When(
  "agent {string} records direct guidance {string} as message {string} in conversation {string}"
) do |agent_id, guidance_text, message_id, conversation_id|
  @guidance_agent_id = agent_id
  @guidance_text = guidance_text
  @guidance_message_id = message_id
  @guidance_conversation_id = conversation_id
  @guidance_task_id = submit_and_execute(
    "guidance_record",
    command_id: "cmd-cuc-guidance-direct",
    actor: { kind: "agent", id: agent_id },
    message_id:,
    conversation_id:,
    source: "mcp_client",
    text: guidance_text,
    anchors: {
      repository_ids: [ "billing" ],
      change_set_id: nil,
      work_item_id: nil,
      attempt_id: nil
    }
  )
  @guidance_task_state = task_request("tasks/get", @guidance_task_id)
end

Then("the guidance Task records one evidence-only fact") do
  task_result = @guidance_task_state.dig("result", "result")
  data = task_result.fetch("structuredContent").fetch("data")
  facts = guidance_events(@guidance_conversation_id)

  assert_acceptance_equal("completed", @guidance_task_state.dig("result", "status"), "Guidance Task")
  assert_acceptance_equal(false, task_result.fetch("isError"), "Guidance tool error flag")
  assert_acceptance_equal("evidence_only", data.fetch("policy_status"), "Guidance policy status")
  assert_acceptance_equal([ "UserUtteranceRecorded" ], facts.map(&:type), "Guidance facts")
  assert_acceptance_equal(@guidance_text, facts.sole.data.fetch("text"), "Recorded guidance text")
end

Then("the available guidance query honestly reports that message as not observed") do
  response = call_tool("guidance_get", { message_id: @guidance_message_id })
  payload = response.dig("result", "structuredContent")

  assert_acceptance_equal("not_found", payload.fetch("status"), "Pre-projection guidance status")
  assert_acceptance_equal(
    "guidance_not_observed",
    payload.dig("data", "code"),
    "Pre-projection guidance reason"
  )
end

When("the guidance reaches the read side") do
  project_guidance(@guidance_conversation_id)
  @guidance_query = call_tool("guidance_get", { message_id: @guidance_message_id })
end

Then(
  "the available guidance preserves its text and unauthenticated attribution without a freshness claim"
) do
  payload = @guidance_query.dig("result", "structuredContent")
  guidance = payload.dig("data", "guidance")

  assert_acceptance_equal("ok", payload.fetch("status"), "Available guidance status")
  assert_acceptance_equal(@guidance_text, guidance.fetch("text"), "Available guidance text")
  assert_acceptance_equal("evidence_only", guidance.fetch("policy_status"), "Available policy status")
  assert_acceptance_equal(
    { "kind" => "agent", "id" => @guidance_agent_id, "authenticated" => false },
    guidance.fetch("actor"),
    "Available attributed actor"
  )
  assert_acceptance(
    (payload.keys & %w[active fresh pending projection_status]).empty?,
    "Guidance query must not claim freshness or activity"
  )
end

When(
  "agent {string} forwards guidance {string} as message {string} in conversation {string}"
) do |agent_id, guidance_text, message_id, conversation_id|
  @forwarded_message_id = message_id
  @forwarded_conversation_id = conversation_id
  @forwarded_task_id = submit_and_execute(
    "guidance_record",
    command_id: "cmd-cuc-guidance-forwarded",
    actor: { kind: "agent", id: agent_id },
    message_id:,
    conversation_id:,
    source: "agent_forwarded",
    text: guidance_text,
    anchors: {
      repository_ids: [],
      change_set_id: nil,
      work_item_id: nil,
      attempt_id: nil
    }
  )
end

When(
  "agent {string} tries to record the same message in conversation {string}"
) do |agent_id, conversation_id|
  @duplicate_guidance_conversation_id = conversation_id
  @duplicate_guidance_command_id = "cmd-cuc-guidance-duplicate"
  @duplicate_guidance_task_id = submit_and_execute(
    "guidance_record",
    command_id: @duplicate_guidance_command_id,
    actor: { kind: "agent", id: agent_id },
    message_id: @forwarded_message_id,
    conversation_id:,
    source: "mcp_client",
    text: "Keep tests on RSpec.",
    anchors: {
      repository_ids: [],
      change_set_id: nil,
      work_item_id: nil,
      attempt_id: nil
    }
  )
  @duplicate_guidance_task_state = task_request("tasks/get", @duplicate_guidance_task_id)
end

Then("the second guidance Task completes with message identity denial") do
  result = @duplicate_guidance_task_state.dig("result", "result")

  assert_acceptance_equal(
    "completed",
    @duplicate_guidance_task_state.dig("result", "status"),
    "Duplicate guidance Task"
  )
  assert_acceptance_equal(true, result.fetch("isError"), "Duplicate guidance error flag")
  assert_acceptance_equal(
    "message_already_recorded",
    result.dig("structuredContent", "data", "code"),
    "Duplicate guidance denial"
  )
end

Then("only the first Conversation owns the forwarded evidence") do
  assert_acceptance_equal(
    [ "UserUtteranceForwardedByAgent" ],
    guidance_events(@forwarded_conversation_id).map(&:type),
    "Forwarded guidance facts"
  )
  assert_acceptance_equal(
    [],
    guidance_events(@duplicate_guidance_conversation_id),
    "Duplicate Conversation facts"
  )
  assert_acceptance_equal(
    [],
    command_events(@duplicate_guidance_command_id),
    "Duplicate guidance completion"
  )
end

Given(
  "guidance {string} is durably recorded as message {string} in conversation {string}"
) do |text, message_id, conversation_id|
  @interpretation_message_id = message_id
  @interpretation_conversation_id = conversation_id
  submit_and_execute(
    "guidance_record",
    command_id: "cmd-cuc-interpretation-source",
    actor: { kind: "agent", id: "host-1" },
    message_id:,
    conversation_id:,
    source: "mcp_client",
    text:,
    anchors: {
      repository_ids: [ "billing" ],
      change_set_id: "CS-CUC-GDN-3",
      work_item_id: nil,
      attempt_id: nil
    }
  )
  assert_acceptance_equal(
    [ "UserUtteranceRecorded" ],
    guidance_events(conversation_id).map(&:type),
    "Interpretation source facts"
  )
end

When("two classifiers independently propose atomic interpretations through Tasks") do
  shared = {
    source_message_id: @interpretation_message_id,
    source_span: { start_character: 4, end_character: 9, text: "RSpec" },
    proposed_decision: {
      statement_kind: "preference",
      topic_id: "testing.framework",
      effect: "prefer",
      modality: "should",
      value: {
        schema: "named-choice/v1",
        name: "rspec",
        items: nil,
        target_kind: nil,
        target_id: nil,
        action: nil
      },
      scope: nil,
      conditions: {
        phases: [ "implementation" ],
        languages: [ "ruby" ],
        tags: [],
        repository_kinds: [],
        artifact_kinds: [],
        environments: []
      },
      validity: { valid_from: nil, valid_until: nil, until_event: nil },
      authority: { actor_id: "user-label", role: "project-owner" },
      enforcement: {
        level: "advisory",
        retroactivity: "future_only",
        on_violation: "warn"
      },
      relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
    },
    ambiguities: []
  }
  first = shared.merge(
    command_id: "cmd-cuc-interpretation-a",
    actor: { kind: "agent", id: "classifier-host-a" },
    interpretation_id: "I-CUC-A",
    classifier: {
      id: "classifier-a",
      version: "decision-classifier-v1",
      ontology_version: 1,
      confidence_millionths: 940_000
    }
  )
  second = shared.merge(
    command_id: "cmd-cuc-interpretation-b",
    actor: { kind: "agent", id: "classifier-host-b" },
    interpretation_id: "I-CUC-B",
    classifier: {
      id: "classifier-b",
      version: "decision-classifier-v1",
      ontology_version: 1,
      confidence_millionths: 810_000
    },
    proposed_decision: shared.fetch(:proposed_decision).merge(
      statement_kind: "directive",
      effect: "require",
      modality: "must",
      enforcement: {
        level: "merge_gate",
        retroactivity: "future_only",
        on_violation: "block"
      }
    )
  )

  @interpretation_tasks = [ first, second ].map do |arguments|
    response = call_tool("decision_interpretation_propose", arguments)
    task_id = response.dig("result", "taskId")
    assert_acceptance(
      task_id,
      "decision_interpretation_propose did not return a Task handle: #{response.inspect}"
    )
    {
      arguments:,
      task_id:
    }
  end
  @interpretation_tasks.map do |entry|
    Thread.new { execute_task(entry.fetch(:task_id)) }
  end.each(&:value)
  @interpretation_tasks.each do |entry|
    entry[:state] = task_request("tasks/get", entry.fetch(:task_id))
  end
end

Then("both proposal Tasks complete while no policy is activated") do
  @interpretation_tasks.each do |entry|
    state = entry.fetch(:state)
    assert_acceptance_equal("completed", state.dig("result", "status"), "Proposal Task status")
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Proposal tool error")
  end
  facts = interpretation_events(@interpretation_message_id)
  assert_acceptance_equal(
    2,
    facts.count { _1.type == "DecisionInterpretationProposed" },
    "Atomic proposal facts"
  )
  assert_acceptance(
    facts.none? { _1.type.include?("Activated") },
    "A proposal command must not activate policy"
  )
end

Then("the hard proposal and its clarification are persisted atomically") do
  facts = interpretation_events(@interpretation_message_id)
  hard_proposal = facts.find { _1.data.fetch("interpretation_id") == "I-CUC-B" && _1.type == "DecisionInterpretationProposed" }
  clarification = facts.find { _1.data.fetch("interpretation_id") == "I-CUC-B" && _1.type == "DecisionClarificationRequired" }

  assert_acceptance(hard_proposal, "The hard proposal fact is missing")
  assert_acceptance(clarification, "The clarification fact is missing")
  assert_acceptance_equal(
    hard_proposal.stream_revision + 1,
    clarification.stream_revision,
    "Hard proposal event-plan revisions"
  )
  assert_acceptance_equal(
    1,
    command_events("cmd-cuc-interpretation-b").length,
    "Hard proposal completion"
  )
end

Then("the available interpretation query honestly reports no proposals before projection") do
  payload = call_tool(
    "decision_interpretation_list",
    { message_id: @interpretation_message_id, after_revision: -1, limit: 20 }
  ).dig("result", "structuredContent")
  assert_acceptance_equal("not_found", payload.fetch("status"), "Pre-projection proposal status")
  assert_acceptance_equal(
    "interpretations_not_observed",
    payload.dig("data", "code"),
    "Pre-projection proposal reason"
  )
end

When("the interpretation proposals reach the read side") do
  project_interpretations(@interpretation_message_id)
end

Then("the available query lists both proposal-only interpretations without a freshness claim") do
  payload = call_tool(
    "decision_interpretation_list",
    { message_id: @interpretation_message_id, after_revision: -1, limit: 20 }
  ).dig("result", "structuredContent")
  proposals = payload.dig("data", "page", "interpretations")

  assert_acceptance_equal("ok", payload.fetch("status"), "Available proposal status")
  assert_acceptance_equal(
    %w[I-CUC-A I-CUC-B],
    proposals.map { _1.fetch("interpretation_id") }.sort,
    "Available proposals"
  )
  assert_acceptance(
    proposals.all? { _1.fetch("policy_status") == "proposal_only" },
    "Projected interpretations must remain proposals"
  )
  assert_acceptance_equal(
    [ "accepted_for_activation", "confirmation_required" ],
    proposals.map { _1.dig("assessment", "status") }.sort,
    "Proposal assessments"
  )
  assert_acceptance(
    (payload.keys & %w[active fresh pending projection_status]).empty?,
    "Interpretation query must not claim freshness or activity"
  )
end

When("the host concurrently accepts both interpretation proposals through Tasks") do
  @interpretation_lifecycle_before_adjudication = interpretation_page(
    @interpretation_message_id
  ).to_h { [ _1.fetch("interpretation_id"), _1.fetch("lifecycle_status") ] }
  inputs = %w[I-CUC-A I-CUC-B].each_with_index.map do |interpretation_id, index|
    interpretation_adjudication_arguments(
      command_id: "cmd-cuc-accept-#{index + 1}",
      interpretation_id:,
      action: "accept"
    )
  end
  @adjudication_tasks = inputs.map do |arguments|
    task_id = call_tool("decision_interpretation_adjudicate", arguments).dig("result", "taskId")
    assert_acceptance(task_id, "Adjudication did not return a Task handle")
    { arguments:, task_id: }
  end
  @adjudication_tasks.map do |entry|
    Thread.new { execute_task(entry.fetch(:task_id)) }
  end.each(&:value)
  @adjudication_tasks.each do |entry|
    entry[:state] = task_request("tasks/get", entry.fetch(:task_id))
  end
end

Then("one acceptance Task succeeds and the other reports a slot conflict") do
  results = @adjudication_tasks.map { _1.fetch(:state).dig("result", "result") }
  assert_acceptance_equal(
    [ false, true ],
    results.map { _1.fetch("isError") }.sort_by { _1 ? 1 : 0 },
    "Acceptance Task outcomes"
  )
  denial = results.find { _1.fetch("isError") }
  assert_acceptance_equal(
    "interpretation_slot_already_accepted",
    denial.dig("structuredContent", "data", "code"),
    "Same-slot denial"
  )
  assert_acceptance_equal(
    1,
    interpretation_events(@interpretation_message_id).count { _1.type == "DecisionInterpretationAccepted" },
    "Accepted interpretation facts"
  )
end

Then("the projected interpretation view remains available at its previous lifecycle state") do
  current = interpretation_page(@interpretation_message_id).to_h do
    [ _1.fetch("interpretation_id"), _1.fetch("lifecycle_status") ]
  end
  assert_acceptance_equal(
    @interpretation_lifecycle_before_adjudication,
    current,
    "Available lifecycle before adjudication projection"
  )
end

When("the interpretation adjudications reach the read side") do
  project_interpretations(@interpretation_message_id)
end

Then("exactly one proposal is accepted for later activation without activating policy") do
  interpretations = interpretation_page(@interpretation_message_id)
  assert_acceptance_equal(
    1,
    interpretations.count { _1.fetch("lifecycle_status") == "accepted" },
    "Projected accepted interpretations"
  )
  assert_acceptance(
    interpretations.all? { _1.fetch("policy_status") == "proposal_only" },
    "Adjudication must not activate policy"
  )
  accepted = interpretations.find { _1.fetch("lifecycle_status") == "accepted" }
  assert_acceptance_equal(
    "accepted_for_activation",
    accepted.dig("adjudication", "outcome"),
    "Accepted adjudication outcome"
  )
  assert_acceptance(
    interpretation_events(@interpretation_message_id).none? { _1.type.include?("Activated") },
    "No activation fact may be emitted"
  )
end

When("the host requests clarification for interpretation {string} through a Task") do |interpretation_id|
  @clarification_interpretation_id = interpretation_id
  @lifecycle_before_clarification = interpretation_page(@interpretation_message_id)
    .find { _1.fetch("interpretation_id") == interpretation_id }
    .fetch("lifecycle_status")
  arguments = interpretation_adjudication_arguments(
    command_id: "cmd-cuc-explicit-clarification",
    interpretation_id:,
    action: "request_clarification",
    clarification: {
      status: "needs_classification",
      questions: [
        {
          field: "scope",
          prompt: "Which repository should this interpretation govern?",
          options: [ "billing", "orders" ]
        }
      ]
    }
  )
  @clarification_task_id = submit_and_execute("decision_interpretation_adjudicate", **arguments)
  @clarification_task_state = task_request("tasks/get", @clarification_task_id)
end

Then("the clarification Task succeeds while the prior view remains available") do
  result = @clarification_task_state.dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Clarification tool error")
  assert_acceptance_equal(
    "clarification_required",
    result.dig("structuredContent", "data", "outcome"),
    "Clarification outcome"
  )
  current = interpretation_page(@interpretation_message_id)
    .find { _1.fetch("interpretation_id") == @clarification_interpretation_id }
  assert_acceptance_equal(
    @lifecycle_before_clarification,
    current.fetch("lifecycle_status"),
    "Available lifecycle before clarification projection"
  )
end

Then("the available interpretation exposes a nonterminal clarification") do
  current = interpretation_page(@interpretation_message_id)
    .find { _1.fetch("interpretation_id") == @clarification_interpretation_id }
  assert_acceptance_equal("clarification_required", current.fetch("lifecycle_status"), "Lifecycle")
  assert_acceptance_equal(
    "request_clarification",
    current.dig("adjudication", "action"),
    "Adjudication action"
  )
  assert_acceptance_equal("proposal_only", current.fetch("policy_status"), "Policy status")
end

When("the host rejects interpretation {string} through a Task") do |interpretation_id|
  arguments = interpretation_adjudication_arguments(
    command_id: "cmd-cuc-reject-interpretation",
    interpretation_id:,
    action: "reject"
  )
  @rejection_task_id = submit_and_execute("decision_interpretation_adjudicate", **arguments)
  @rejection_task_state = task_request("tasks/get", @rejection_task_id)
end

Then("the rejection Task succeeds while the clarification view remains available") do
  result = @rejection_task_state.dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Rejection tool error")
  assert_acceptance_equal(
    "rejected",
    result.dig("structuredContent", "data", "outcome"),
    "Rejection outcome"
  )
  current = interpretation_page(@interpretation_message_id)
    .find { _1.fetch("interpretation_id") == @clarification_interpretation_id }
  assert_acceptance_equal(
    "clarification_required",
    current.fetch("lifecycle_status"),
    "Available lifecycle before rejection projection"
  )
end

Then("the available interpretation is rejected without activating policy") do
  current = interpretation_page(@interpretation_message_id)
    .find { _1.fetch("interpretation_id") == @clarification_interpretation_id }
  assert_acceptance_equal("rejected", current.fetch("lifecycle_status"), "Lifecycle")
  assert_acceptance_equal("reject", current.dig("adjudication", "action"), "Adjudication action")
  assert_acceptance_equal("proposal_only", current.fetch("policy_status"), "Policy status")
  assert_acceptance(
    interpretation_events(@interpretation_message_id).none? { _1.type.include?("Activated") },
    "No activation fact may be emitted"
  )
end

Given("these interpretations are accepted for activation:") do |table|
  @decision_activation_candidates = table.hashes.each_with_index.map do |row, index|
    interpretation_id = row.fetch("interpretation_id")
    message_id = row.fetch("message_id")
    decision_id = row.fetch("decision_id")
    suffix = index + 1

    guidance_task = submit_and_execute(
      "guidance_record",
      command_id: "cmd-cuc-decision-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-CUC-DEC-#{suffix}",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "billing" ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    )
    proposal_task = submit_and_execute(
      "decision_interpretation_propose",
      command_id: "cmd-cuc-decision-proposal-#{suffix}",
      actor: { kind: "agent", id: "classifier-host-#{suffix}" },
      interpretation_id:,
      source_message_id: message_id,
      source_span: { start_character: 4, end_character: 9, text: "RSpec" },
      classifier: {
        id: "classifier-#{suffix}",
        version: "decision-classifier-v1",
        ontology_version: 1,
        confidence_millionths: 940_000
      },
      proposed_decision: {
        statement_kind: "preference",
        topic_id: "testing.framework",
        effect: "prefer",
        modality: "should",
        value: {
          schema: "named-choice/v1",
          name: "rspec",
          items: nil,
          target_kind: nil,
          target_id: nil,
          action: nil
        },
        scope: nil,
        conditions: {
          phases: [ "implementation" ],
          languages: [ "ruby" ],
          tags: [],
          repository_kinds: [],
          artifact_kinds: [],
          environments: []
        },
        validity: { valid_from: nil, valid_until: nil, until_event: nil },
        authority: { actor_id: "user-label", role: "project-owner" },
        enforcement: {
          level: "advisory",
          retroactivity: "future_only",
          on_violation: "warn"
        },
        relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
      },
      ambiguities: []
    )
    adjudication_task = submit_and_execute(
      "decision_interpretation_adjudicate",
      command_id: "cmd-cuc-decision-adjudication-#{suffix}",
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: message_id,
      interpretation_id:,
      action: "accept",
      rationale: {
        code: "user_confirmed",
        summary: "The proposed reading matches the intended guidance."
      },
      clarification: nil
    )

    [ guidance_task, proposal_task, adjudication_task ].each do |task_id|
      state = task_request("tasks/get", task_id)
      assert_acceptance_equal("completed", state.dig("result", "status"), "Setup Task status")
      assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Setup Task error")
    end
    acceptance = interpretation_events(message_id).find do |event|
      event.type == "DecisionInterpretationAccepted"
    end
    assert_acceptance(acceptance, "Interpretation #{interpretation_id} was not accepted")

    {
      interpretation_id:,
      message_id:,
      decision_id:,
      activation_command_id: "cmd-cuc-decision-activation-#{suffix}"
    }
  end
end

Then("acceptance has emitted no Decision facts") do
  @decision_activation_candidates.each do |candidate|
    assert_acceptance_equal(
      [],
      decision_events(candidate.fetch(:decision_id)),
      "Pre-activation Decision facts"
    )
  end
  assert_acceptance_equal([], decision_partition_events, "Pre-activation partition facts")
end

When(
  "the host activates interpretation {string} as Decision {string} through a Task"
) do |interpretation_id, decision_id|
  candidate = @decision_activation_candidates.find do |entry|
    entry.fetch(:interpretation_id) == interpretation_id && entry.fetch(:decision_id) == decision_id
  end
  assert_acceptance(candidate, "No accepted activation candidate matches #{interpretation_id}/#{decision_id}")
  @decision_activation = candidate
  @decision_activation_task_id = submit_and_execute(
    "decision_activate",
    command_id: candidate.fetch(:activation_command_id),
    actor: { kind: "orchestrator", id: "guidance-host" },
    decision_id:,
    interpretation_id:,
    rationale: { code: "user_confirmed", summary: "Activate the accepted policy." }
  )
  @decision_activation_state = task_request("tasks/get", @decision_activation_task_id)
end

Then("the activation Task succeeds with one complete consistency boundary") do
  result = @decision_activation_state.dig("result", "result")
  assert_acceptance_equal("completed", @decision_activation_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Activation error flag")
  data = result.dig("structuredContent", "data")
  decision_id = @decision_activation.fetch(:decision_id)
  slot_id = data.dig("slot", "slot_id")

  assert_acceptance_equal(
    %w[DecisionRecorded DecisionActivated],
    decision_events(decision_id).map(&:type),
    "Decision event plan"
  )
  assert_acceptance_equal(
    %w[DecisionSlotOpened DecisionSlotHeadChanged],
    decision_slot_events(slot_id).map(&:type),
    "Decision slot event plan"
  )
  assert_acceptance_equal(
    [ "DecisionPartitionAdvanced" ],
    decision_partition_events.map(&:type),
    "Decision partition event plan"
  )
  assert_acceptance_equal(
    1,
    command_events(@decision_activation.fetch(:activation_command_id)).length,
    "Decision activation completion"
  )
end

Then("Decision {string} is honestly not observed before projection") do |decision_id|
  payload = decision_view(decision_id)
  assert_acceptance_equal("not_found", payload.fetch("status"), "Unprojected Decision status")
  assert_acceptance_equal("decision_not_observed", payload.dig("data", "code"), "Unprojected Decision reason")
end

When("the DecisionRecorded fact for {string} reaches the read side") do |decision_id|
  project_decision_recorded(decision_id)
end

Then("the available Decision {string} is recorded without a freshness claim") do |decision_id|
  payload = decision_view(decision_id)
  decision = payload.dig("data", "decision")
  assert_acceptance_equal("ok", payload.fetch("status"), "Recorded Decision status")
  assert_acceptance_equal("recorded", decision.fetch("policy_status"), "Decision policy status")
  assert_acceptance_equal(nil, decision.fetch("activated"), "Premature activation evidence")
  assert_acceptance(
    (payload.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "Decision query must not claim freshness"
  )
end

When("the remaining facts for Decision {string} reach the read side") do |decision_id|
  project_remaining_decision_facts(decision_id)
end

Then("the available Decision {string} is active without a freshness claim") do |decision_id|
  payload = decision_view(decision_id)
  decision = payload.dig("data", "decision")
  assert_acceptance_equal("ok", payload.fetch("status"), "Active Decision status")
  assert_acceptance_equal("active", decision.fetch("policy_status"), "Decision policy status")
  assert_acceptance(decision.fetch("activated"), "Activation evidence is missing")
  assert_acceptance_equal(
    [ "repo:billing:testing" ],
    decision.fetch("partitions").map { _1.fetch("partition_id") },
    "Decision partitions"
  )
  assert_acceptance(
    (payload.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "Decision query must not claim freshness"
  )
end

When("the host concurrently activates all accepted interpretations through Tasks") do
  @decision_activation_candidates.each do |candidate|
    response = call_tool(
      "decision_activate",
      {
        command_id: candidate.fetch(:activation_command_id),
        actor: { kind: "orchestrator", id: "guidance-host" },
        decision_id: candidate.fetch(:decision_id),
        interpretation_id: candidate.fetch(:interpretation_id),
        rationale: { code: "user_confirmed", summary: "Activate the accepted policy." }
      }
    )
    candidate[:task_id] = response.dig("result", "taskId")
    assert_acceptance(candidate.fetch(:task_id), "Activation did not return a Task handle")
  end
  @decision_activation_candidates.map do |candidate|
    Thread.new { execute_task(candidate.fetch(:task_id)) }
  end.each(&:value)
  @decision_activation_candidates.each do |candidate|
    candidate[:state] = task_request("tasks/get", candidate.fetch(:task_id))
  end
end

Then("one activation Task succeeds and the other reports an occupied Decision slot") do
  results = @decision_activation_candidates.map { _1.fetch(:state).dig("result", "result") }
  assert_acceptance_equal(
    [ false, true ],
    results.map { _1.fetch("isError") }.sort_by { _1 ? 1 : 0 },
    "Decision activation Task outcomes"
  )
  @winning_activation = @decision_activation_candidates.find do |candidate|
    !candidate.fetch(:state).dig("result", "result", "isError")
  end
  @losing_activation = @decision_activation_candidates.find do |candidate|
    candidate.fetch(:state).dig("result", "result", "isError")
  end
  denial = @losing_activation.fetch(:state).dig("result", "result", "structuredContent")
  assert_acceptance_equal("decision_slot_occupied", denial.dig("data", "code"), "Slot denial")
  assert_acceptance_equal(1, decision_partition_events.length, "Winning partition fact")
end

Then("the losing activation writes no Decision or command facts") do
  assert_acceptance_equal(
    [],
    decision_events(@losing_activation.fetch(:decision_id)),
    "Losing Decision facts"
  )
  assert_acceptance_equal(
    [],
    command_events(@losing_activation.fetch(:activation_command_id)),
    "Losing command facts"
  )
  assert_acceptance_equal(
    2,
    decision_events(@winning_activation.fetch(:decision_id)).length,
    "Winning Decision facts"
  )
  assert_acceptance_equal(
    1,
    command_events(@winning_activation.fetch(:activation_command_id)).length,
    "Winning command facts"
  )
end

Given("these correction interpretations are accepted for Decision {string}:") do |decision_id, table|
  @decision_correction_candidates = table.hashes.each_with_index.map do |row, index|
    accept_correction_interpretation(
      decision_id:,
      interpretation_id: row.fetch("interpretation_id"),
      message_id: row.fetch("message_id"),
      value: row.fetch("value"),
      suffix: index + 1
    )
  end
end

When(
  "the host corrects Decision {string} with interpretation {string} using the available head"
) do |decision_id, interpretation_id|
  @decision_correction_expected_head = decision_view(decision_id)
    .dig("data", "decision", "current_head", "event")
  candidate = @decision_correction_candidates.find do |entry|
    entry.fetch(:decision_id) == decision_id && entry.fetch(:interpretation_id) == interpretation_id
  end
  assert_acceptance(candidate, "No accepted correction matches #{decision_id}/#{interpretation_id}")
  @decision_correction = candidate
  @decision_correction_task_id = submit_and_execute(
    "decision_correct",
    command_id: candidate.fetch(:command_id),
    actor: { kind: "orchestrator", id: "guidance-host" },
    decision_id:,
    interpretation_id:,
    expected_head: @decision_correction_expected_head,
    rationale: {
      code: "normalization_corrected",
      summary: "Apply the accepted correction."
    }
  )
  @decision_correction_state = task_request("tasks/get", @decision_correction_task_id)
end

Then("the correction Task succeeds while the previous Decision view remains available") do
  result = @decision_correction_state.dig("result", "result")
  assert_acceptance_equal("completed", @decision_correction_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Correction error flag")
  data = result.dig("structuredContent", "data")
  decision_id = @decision_correction.fetch(:decision_id)
  slot_id = data.dig("slot", "slot_id")

  assert_acceptance_equal(
    %w[DecisionRecorded DecisionActivated DecisionDefinitionCorrected],
    decision_events(decision_id).map(&:type),
    "Decision correction event plan"
  )
  assert_acceptance_equal(
    %w[DecisionSlotOpened DecisionSlotHeadChanged DecisionSlotHeadChanged],
    decision_slot_events(slot_id).map(&:type),
    "Decision correction slot plan"
  )
  assert_acceptance_equal(
    %w[DecisionPartitionAdvanced DecisionPartitionAdvanced],
    decision_partition_events.map(&:type),
    "Decision correction partition plan"
  )
  assert_acceptance_equal(
    1,
    command_events(@decision_correction.fetch(:command_id)).length,
    "Decision correction completion"
  )

  view = decision_view(decision_id)
  decision = view.dig("data", "decision")
  assert_acceptance_equal("ok", view.fetch("status"), "Stale Decision availability")
  assert_acceptance_equal(
    @decision_activation.fetch(:interpretation_id),
    decision.fetch("interpretation_id"),
    "Previously projected interpretation"
  )
  assert_acceptance_equal(0, decision.fetch("correction_count"), "Unprojected correction count")
  assert_acceptance_equal(
    @decision_correction_expected_head.fetch("event_id"),
    decision.dig("current_head", "event", "event_id"),
    "Previously projected head"
  )
end

When(
  "the host corrects Decision {string} with interpretation {string} using the same stale head"
) do |decision_id, interpretation_id|
  candidate = @decision_correction_candidates.find do |entry|
    entry.fetch(:decision_id) == decision_id && entry.fetch(:interpretation_id) == interpretation_id
  end
  assert_acceptance(candidate, "No accepted stale correction matches #{decision_id}/#{interpretation_id}")
  @stale_decision_correction = candidate
  @stale_decision_correction_task_id = submit_and_execute(
    "decision_correct",
    command_id: candidate.fetch(:command_id),
    actor: { kind: "orchestrator", id: "guidance-host" },
    decision_id:,
    interpretation_id:,
    expected_head: @decision_correction_expected_head,
    rationale: {
      code: "normalization_corrected",
      summary: "Apply the accepted correction."
    }
  )
  @stale_decision_correction_state = task_request("tasks/get", @stale_decision_correction_task_id)
end

Then("the stale correction Task reports a Decision revision conflict without new policy facts") do
  result = @stale_decision_correction_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @stale_decision_correction_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(true, result.fetch("isError"), "Stale correction error flag")
  assert_acceptance_equal("conflict", content.fetch("status"), "Stale correction status")
  assert_acceptance_equal("decision_revision_changed", content.dig("data", "code"), "Stale correction denial")
  assert_acceptance_equal(
    [],
    command_events(@stale_decision_correction.fetch(:command_id)),
    "Denied correction command facts"
  )
  assert_acceptance_equal(
    1,
    decision_events(@stale_decision_correction.fetch(:decision_id)).count {
      _1.type == "DecisionDefinitionCorrected"
    },
    "Completed correction facts"
  )
end

When("the correction fact for Decision {string} reaches the read side") do |decision_id|
  project_decision_correction(decision_id)
end

Then(
  "the available Decision {string} exposes correction interpretation {string} without a freshness claim"
) do |decision_id, interpretation_id|
  payload = decision_view(decision_id)
  decision = payload.dig("data", "decision")
  corrected = decision.fetch("corrected")
  assert_acceptance_equal("ok", payload.fetch("status"), "Corrected Decision status")
  assert_acceptance_equal("active", decision.fetch("policy_status"), "Corrected policy status")
  assert_acceptance_equal(interpretation_id, decision.fetch("interpretation_id"), "Correction interpretation")
  assert_acceptance_equal(1, decision.fetch("correction_count"), "Correction count")
  assert_acceptance_equal(
    "DecisionDefinitionCorrected",
    corrected.dig("event", "type"),
    "Correction evidence"
  )
  assert_acceptance_equal(
    corrected.dig("event", "event_id"),
    decision.dig("current_head", "event", "event_id"),
    "Current Decision head"
  )
  assert_acceptance(
    (payload.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "Decision query must not claim freshness"
  )
end

Given(
  "agent {string} has active Attempt {string} for WorkItem {string} in ChangeSet {string} and repository {string}"
) do |agent_id, attempt_id, work_item_id, change_set_id, repository_id|
  @choice_agent_id = agent_id
  @choice_context = {
    workspace_id: nil,
    repository_id:,
    change_set_id:,
    work_item_id:,
    attempt_id:,
    phase: "implementation",
    language: "ruby",
    paths: [ "spec/models/order_spec.rb" ],
    environment: "test",
    agent_role: "implementer"
  }
  setup_tasks = []
  setup_tasks << submit_and_execute(
    "change_set_create",
    command_id: "cmd-cuc-choice-create-#{change_set_id}",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    goal: "Record a significant agent choice",
    acceptance_criteria: [ "The accepted choice remains attributable" ]
  )
  setup_tasks << submit_and_execute(
    "work_item_create",
    command_id: "cmd-cuc-choice-create-#{work_item_id}",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:,
    work_item_id:,
    repository_id:,
    goal: "Select the testing framework",
    acceptance_criteria: [ "The selected framework is coordinated" ]
  )
  setup_tasks << submit_and_execute(
    "change_set_activate",
    command_id: "cmd-cuc-choice-activate-#{change_set_id}",
    actor: { kind: "agent", id: "planner-1" },
    change_set_id:
  )
  activation = change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
  assert_acceptance(activation, "ChangeSet #{change_set_id} has no activation fact")
  Coordinator::Container["process_managers.change_set_readiness"].call(activation)
  setup_tasks << submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-choice-acquire-#{attempt_id}",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id:,
    attempt_id:,
    base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
  )

  setup_tasks.each do |task_id|
    state = task_request("tasks/get", task_id)
    assert_acceptance_equal("completed", state.dig("result", "status"), "Choice setup Task status")
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Choice setup error")
  end
end

When("the agent resolves the available testing-framework context") do
  payload = call_tool(
    "decision_resolve",
    { topic_id: "testing.framework", context: @choice_context }
  ).dig("result", "structuredContent")
  assert_acceptance_equal("ok", payload.fetch("status"), "Decision context status")
  @choice_decision_context = payload.dig("data", "decision_context")
  assert_acceptance(@choice_decision_context, "decision_resolve returned no decision context")
end

When(
  "the agent records testing-framework choice {string} as {string} through a Task"
) do |option_id, choice_id|
  @choice_id = choice_id
  @choice_command_id = "cmd-cuc-choice-record-#{choice_id}"
  @choice_task_id = submit_and_execute(
    "agent_choice_record",
    command_id: @choice_command_id,
    actor: { kind: "agent", id: @choice_agent_id },
    choice_id:,
    choice_type: "testing.framework",
    selected: { option_id:, summary: option_id.capitalize },
    alternatives: [ { option_id: "minitest", summary: "Minitest" } ],
    reason_summary: "Use the framework that fits the available coordination policy.",
    context: @choice_context,
    decision_context: @choice_decision_context
  )
  @choice_task_state = task_request("tasks/get", @choice_task_id)
end

Then("the choice Task succeeds with accepted authoritative facts") do
  result = @choice_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @choice_task_state.dig("result", "status"), "Choice Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Choice Task error flag")
  assert_acceptance_equal("ok", content.fetch("status"), "Choice result status")
  assert_acceptance_equal("accepted", content.dig("data", "outcome"), "Choice outcome")
  assert_acceptance_equal(
    %w[AgentChoiceRecorded AgentChoiceAccepted],
    agent_choice_events(@choice_id).map(&:type),
    "AgentChoice event plan"
  )
  assert_acceptance_equal(1, command_events(@choice_command_id).length, "Choice command completion")
end

Then("AgentChoice {string} is honestly not observed before projection") do |choice_id|
  payload = agent_choice_view(choice_id)
  assert_acceptance_equal("not_found", payload.fetch("status"), "Unprojected AgentChoice status")
  assert_acceptance_equal(
    "agent_choice_not_observed",
    payload.dig("data", "code"),
    "Unprojected AgentChoice reason"
  )
end

When("the AgentChoiceRecorded fact for {string} reaches the read side") do |choice_id|
  project_agent_choice_event(choice_id, "AgentChoiceRecorded")
end

Then("the available AgentChoice {string} is recorded without a freshness claim") do |choice_id|
  payload = agent_choice_view(choice_id)
  choice = payload.dig("data", "choice")
  assert_acceptance_equal("ok", payload.fetch("status"), "Recorded AgentChoice status")
  assert_acceptance_equal("recorded", choice.fetch("observation_status"), "Choice observation status")
  assert_acceptance_equal(nil, choice.fetch("accepted"), "Premature acceptance evidence")
  assert_acceptance_equal("AgentChoiceRecorded", choice.dig("recorded", "event", "type"), "Recorded evidence")
  assert_acceptance(
    (choice.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "AgentChoice view must not claim freshness"
  )
end

When("the AgentChoiceAccepted fact for {string} reaches the read side") do |choice_id|
  project_agent_choice_event(choice_id, "AgentChoiceAccepted")
end

Then("the available AgentChoice {string} is accepted without a freshness claim") do |choice_id|
  payload = agent_choice_view(choice_id)
  choice = payload.dig("data", "choice")
  assert_acceptance_equal("ok", payload.fetch("status"), "Accepted AgentChoice status")
  assert_acceptance_equal("accepted", choice.fetch("observation_status"), "Choice observation status")
  assert_acceptance_equal("no_policy", choice.dig("assessment", "basis"), "Choice assessment")
  assert_acceptance_equal("AgentChoiceAccepted", choice.dig("accepted", "event", "type"), "Accepted evidence")
  assert_acceptance(
    (choice.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "AgentChoice view must not claim freshness"
  )
end

Then("the older Decision context remains available without a freshness claim") do
  payload = call_tool(
    "decision_resolve",
    { topic_id: "testing.framework", context: @choice_context }
  ).dig("result", "structuredContent")
  available = payload.dig("data", "decision_context")
  assert_acceptance_equal("ok", payload.fetch("status"), "Lagging Decision context status")
  assert_acceptance_equal(
    @choice_decision_context.fetch("digest"),
    available.fetch("digest"),
    "Lagging Decision context digest"
  )
  assert_acceptance_equal(nil, available.dig("document", "effective_decision"), "Lagging policy evidence")
  assert_acceptance(
    (payload.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "Decision context must not claim freshness"
  )
end

Then("the choice Task reports stale context and explains how to refresh") do
  result = @choice_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @choice_task_state.dig("result", "status"), "Choice Task status")
  assert_acceptance_equal(true, result.fetch("isError"), "Stale choice error flag")
  assert_acceptance_equal("stale_context", content.fetch("status"), "Stale choice status")
  assert_acceptance_equal("stale_decision_context", content.dig("data", "code"), "Stale choice reason")
  refresh = content.fetch("next_actions").find { _1.fetch("tool") == "decision_resolve" }
  assert_acceptance(refresh, "Stale choice result must explain how to refresh Decision context")
end

Then("the stale choice writes no AgentChoice or command facts") do
  assert_acceptance_equal([], agent_choice_events(@choice_id), "Denied AgentChoice facts")
  assert_acceptance_equal([], command_events(@choice_command_id), "Denied choice command facts")
  assert_acceptance_equal("not_found", agent_choice_view(@choice_id).fetch("status"), "Denied Choice view")
end
