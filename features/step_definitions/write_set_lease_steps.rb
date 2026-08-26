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

When("both agents concurrently reserve their disjoint files") do
  @disjoint_reservations = @lease_participants.map.with_index do |participant, index|
    arguments = {
      command_id: "cmd-cuc-lse-disjoint-#{index + 1}",
      actor: { kind: "agent", id: participant.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: participant.fetch(:work_item_id),
      attempt_id: participant.fetch(:attempt_id),
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path: participant.fetch(:unique_path) } ],
      lease_duration_seconds: 300
    }
    task_id = call_tool("write_set_reserve", arguments).dig("result", "taskId")
    participant.merge(task_id:, arguments:)
  end

  @disjoint_reservations.map do |reservation|
    Thread.new { execute_task(reservation.fetch(:task_id)) }
  end.each(&:value)
  @disjoint_reservations.each do |reservation|
    reservation[:state] = task_request("tasks/get", reservation.fetch(:task_id))
    reservation[:outcome] = reservation.dig(:state, "result", "result", "structuredContent")
  end
end

Then("both disjoint reservation Tasks succeed with complete write sets") do
  assert_acceptance_equal(
    [ "ok", "ok" ],
    @disjoint_reservations.map { _1.dig(:outcome, "status") },
    "Disjoint reservation outcomes"
  )
  @disjoint_reservations.each do |reservation|
    write_set = write_set_events(reservation.fetch(:attempt_id)).sole
    assert_acceptance_equal(
      [ reservation.fetch(:unique_path) ],
      write_set.data.fetch("resources").map { _1.fetch("resource_path") },
      "Disjoint complete write set"
    )
    assert_acceptance_equal(1, lease_events(reservation.fetch(:unique_path)).length, "Disjoint lease facts")
  end
end

When(
  "both agents concurrently reserve aliases {string} and {string}"
) do |first_path, second_path|
  @alias_paths = [ first_path, second_path ]
  @alias_reservations = @lease_participants.zip(@alias_paths).map.with_index do |(participant, path), index|
    arguments = {
      command_id: "cmd-cuc-lse-alias-#{index + 1}",
      actor: { kind: "agent", id: participant.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: participant.fetch(:work_item_id),
      attempt_id: participant.fetch(:attempt_id),
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path: } ],
      lease_duration_seconds: 300
    }
    task_id = call_tool("write_set_reserve", arguments).dig("result", "taskId")
    participant.merge(task_id:, arguments:)
  end

  @alias_reservations.map do |reservation|
    Thread.new { execute_task(reservation.fetch(:task_id)) }
  end.each(&:value)
  @alias_reservations.each do |reservation|
    reservation[:state] = task_request("tasks/get", reservation.fetch(:task_id))
    reservation[:outcome] = reservation.dig(:state, "result", "result", "structuredContent")
  end
end

Then("one normalized reservation wins and the loser owns no lease") do
  assert_acceptance_equal(
    [ "busy", "ok" ],
    @alias_reservations.map { _1.dig(:outcome, "status") }.sort,
    "Alias reservation outcomes"
  )
  winner = @alias_reservations.find { _1.dig(:outcome, "status") == "ok" }
  loser = @alias_reservations.find { _1.dig(:outcome, "status") == "busy" }
  normalized_path = "db/schema.rb"

  assert_acceptance_equal(
    [ normalized_path ],
    write_set_events(winner.fetch(:attempt_id)).sole.data.fetch("resources").map { _1.fetch("resource_path") },
    "Normalized winning path"
  )
  assert_acceptance_equal([], write_set_events(loser.fetch(:attempt_id)), "Alias loser write set")
  assert_acceptance_equal(1, lease_events(normalized_path).length, "Normalized lease lifecycle")
end

When(
  "agent {string} cancels a queued reservation for {string} before execution"
) do |agent_id, path|
  @cancelled_reservation_owner = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  @cancelled_reservation_path = path
  @cancelled_reservation_command_id = "cmd-cuc-lse-cancel-reservation"
  arguments = {
    command_id: @cancelled_reservation_command_id,
    actor: { kind: "agent", id: agent_id },
    change_set_id: @lease_change_set_id,
    work_item_id: @cancelled_reservation_owner.fetch(:work_item_id),
    attempt_id: @cancelled_reservation_owner.fetch(:attempt_id),
    repository_id: "billing",
    base_commit_oid: "a" * 40,
    resources: [ { kind: "file", path: } ],
    lease_duration_seconds: 300
  }
  @cancelled_reservation_task_id = call_tool("write_set_reserve", arguments).dig("result", "taskId")
  task_request("tasks/cancel", @cancelled_reservation_task_id)
  execute_task(@cancelled_reservation_task_id)
  @cancelled_reservation_state = task_request("tasks/get", @cancelled_reservation_task_id)
end

Then("the cancelled reservation writes no lease fact") do
  assert_acceptance_equal("cancelled", @cancelled_reservation_state.dig("result", "status"), "Task status")
  assert_acceptance_equal([], lease_events(@cancelled_reservation_path), "Cancelled lease facts")
  assert_acceptance_equal(
    [],
    write_set_events(@cancelled_reservation_owner.fetch(:attempt_id)),
    "Cancelled Attempt write set"
  )
  assert_acceptance_equal([], command_events(@cancelled_reservation_command_id), "Cancelled command facts")
end

When("agent {string} deliberately reserves {string}") do |agent_id, path|
  participant = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-lse-deliberate-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id: @lease_change_set_id,
    work_item_id: participant.fetch(:work_item_id),
    attempt_id: participant.fetch(:attempt_id),
    repository_id: "billing",
    base_commit_oid: "a" * 40,
    resources: [ { kind: "file", path: } ],
    lease_duration_seconds: 300
  )
  @successor_result = task_request("tasks/get", task_id).dig(
    "result", "result", "structuredContent", "data"
  )
end

Then("the successor obtains fencing token {int}") do |expected_token|
  assert_acceptance_equal(
    expected_token,
    @successor_result.fetch("resources").sole.fetch("fencing_token"),
    "Successor fencing token"
  )
end

When("the predecessor renews its exact lease set before the old deadline") do
  @renewed_predecessor_task_id = Timecop.freeze(@expiry_started_at + 10) do
    task_id = call_tool(
      "lease_renew",
      {
        command_id: "cmd-cuc-renew-predecessor",
        actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
        change_set_id: @lease_change_set_id,
        work_item_id: @expiry_predecessor.fetch(:work_item_id),
        attempt_id: @expiry_predecessor.fetch(:attempt_id),
        lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
        leases: @expiry_predecessor_result.fetch("resources").map do |reference|
          reference.slice("resource_key_hash", "lease_id", "fencing_token").transform_keys(&:to_sym)
        end,
        lease_duration_seconds: 60
      }
    ).dig("result", "taskId")
    execute_task(task_id)
    task_id
  end
  @renewed_predecessor_state = task_request("tasks/get", @renewed_predecessor_task_id)
  @renewed_predecessor_result = @renewed_predecessor_state.dig(
    "result", "result", "structuredContent", "data"
  )
end

Then("the authoritative deadline moves beyond the old expiry") do
  assert_acceptance_equal("completed", @renewed_predecessor_state.dig("result", "status"), "Renewal Task")
  assert_acceptance_equal(false, @renewed_predecessor_state.dig("result", "result", "isError"), "Renewal error")
  assert_acceptance(
    @renewed_predecessor_result.fetch("expires_at") > @expiry_predecessor_result.fetch("expires_at"),
    "Renewed deadline must be later"
  )
end

When(
  "agent {string} deliberately reserves after the old deadline but before the renewed deadline"
) do |agent_id|
  participant = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  @renewal_contender_task_id = Timecop.freeze(@expiry_started_at + 31) do
    task_id = call_tool(
      "write_set_reserve",
      {
        command_id: "cmd-cuc-renew-contender",
        actor: { kind: "agent", id: agent_id },
        change_set_id: @lease_change_set_id,
        work_item_id: participant.fetch(:work_item_id),
        attempt_id: participant.fetch(:attempt_id),
        repository_id: "billing",
        base_commit_oid: "a" * 40,
        resources: [ { kind: "file", path: @expiry_path } ],
        lease_duration_seconds: 300
      }
    ).dig("result", "taskId")
    execute_task(task_id)
    task_id
  end
  @renewal_contender_state = task_request("tasks/get", @renewal_contender_task_id)
end

Then("the contender remains busy with the renewed deadline") do
  outcome = @renewal_contender_state.dig("result", "result", "structuredContent")

  assert_acceptance_equal("completed", @renewal_contender_state.dig("result", "status"), "Contender Task")
  assert_acceptance_equal("busy", outcome.fetch("status"), "Contender outcome")
  assert_acceptance_equal(
    @renewed_predecessor_result.fetch("expires_at"),
    outcome.dig("data", "details", "expires_at"),
    "Authoritative busy deadline"
  )
  assert_acceptance_equal([], write_set_events(@lease_participants.last.fetch(:attempt_id)), "Contender write set")
end

When("the exact release command is retried through another Task") do
  arguments = {
    command_id: "cmd-cuc-release-set",
    actor: { kind: "agent", id: @release_agent_id },
    change_set_id: @release_change_set_id,
    work_item_id: @release_work_item_id,
    attempt_id: @release_attempt_id,
    lease_set_id: @release_reservation.fetch("lease_set_id"),
    leases: @release_reservation.fetch("resources").map do |reference|
      reference.slice("resource_key_hash", "lease_id", "fencing_token").transform_keys(&:to_sym)
    end
  }
  @release_retry_task_id = call_tool("lease_release", arguments).dig("result", "taskId")
  execute_task(@release_retry_task_id)
  @release_retry_task_state = task_request("tasks/get", @release_retry_task_id)
end

Then("both release Task handles expose one logical result") do
  assert_acceptance_equal(
    @release_task_state.dig("result", "result"),
    @release_retry_task_state.dig("result", "result"),
    "Release replay result"
  )
  assert_acceptance_equal(1, write_set_release_events(@release_attempt_id).length, "Write-set releases")
  assert_acceptance_equal(1, command_events("cmd-cuc-release-set").length, "Release command completions")
end

When("the predecessor releases its exact lease set") do
  @predecessor_release_task_id = Timecop.freeze(@expiry_started_at + 1) do
    task_id = call_tool(
      "lease_release",
      {
        command_id: "cmd-cuc-release-predecessor",
        actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
        change_set_id: @lease_change_set_id,
        work_item_id: @expiry_predecessor.fetch(:work_item_id),
        attempt_id: @expiry_predecessor.fetch(:attempt_id),
        lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
        leases: @expiry_predecessor_result.fetch("resources").map do |reference|
          reference.slice("resource_key_hash", "lease_id", "fencing_token").transform_keys(&:to_sym)
        end
      }
    ).dig("result", "taskId")
    execute_task(task_id)
    task_id
  end
  @predecessor_release_state = task_request("tasks/get", @predecessor_release_task_id)
end

Then("the authoritative release succeeds") do
  assert_acceptance_equal("completed", @predecessor_release_state.dig("result", "status"), "Release Task")
  assert_acceptance_equal(false, @predecessor_release_state.dig("result", "result", "isError"), "Release error")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseReleased" ],
    lease_events(@expiry_path).map(&:type),
    "Released lifecycle"
  )
end

When("agent {string} deliberately reserves after the release") do |agent_id|
  participant = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  task_id = Timecop.freeze(@expiry_started_at + 2) do
    submit_and_execute(
      "write_set_reserve",
      command_id: "cmd-cuc-release-successor",
      actor: { kind: "agent", id: agent_id },
      change_set_id: @lease_change_set_id,
      work_item_id: participant.fetch(:work_item_id),
      attempt_id: participant.fetch(:attempt_id),
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path: @expiry_path } ],
      lease_duration_seconds: 300
    )
  end
  @successor_result = task_request("tasks/get", task_id).dig(
    "result", "result", "structuredContent", "data"
  )
end

When("the expired predecessor tries to renew its old fence") do
  @expired_predecessor_renewal_task_id = Timecop.freeze(@expiry_started_at + 33) do
    task_id = call_tool(
      "lease_renew",
      {
        command_id: "cmd-cuc-expired-predecessor-renew",
        actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
        change_set_id: @lease_change_set_id,
        work_item_id: @expiry_predecessor.fetch(:work_item_id),
        attempt_id: @expiry_predecessor.fetch(:attempt_id),
        lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
        leases: @expiry_predecessor_result.fetch("resources").map do |reference|
          reference.slice("resource_key_hash", "lease_id", "fencing_token").transform_keys(&:to_sym)
        end,
        lease_duration_seconds: 300
      }
    ).dig("result", "taskId")
    execute_task(task_id)
    task_id
  end
  @expired_predecessor_renewal_state = task_request("tasks/get", @expired_predecessor_renewal_task_id)
end

Then("the predecessor renewal is denied without affecting the successor") do
  outcome = @expired_predecessor_renewal_state.dig("result", "result", "structuredContent")
  assert_acceptance_equal("completed", @expired_predecessor_renewal_state.dig("result", "status"), "Renewal Task")
  assert_acceptance_equal(true, @expired_predecessor_renewal_state.dig("result", "result", "isError"), "Renewal error")
  assert_acceptance(%w[lease_set_expired lease_set_not_current].include?(outcome.dig("data", "code")), "Renewal denial")
  assert_acceptance_equal(2, lease_events(@expiry_path).count { _1.type == "ResourceLeaseAcquired" }, "Owners")
end

When("the expired predecessor tries to release its old fence") do
  @expired_predecessor_release_task_id = Timecop.freeze(@expiry_started_at + 34) do
    task_id = call_tool(
      "lease_release",
      {
        command_id: "cmd-cuc-expired-predecessor-release",
        actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
        change_set_id: @lease_change_set_id,
        work_item_id: @expiry_predecessor.fetch(:work_item_id),
        attempt_id: @expiry_predecessor.fetch(:attempt_id),
        lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
        leases: @expiry_predecessor_result.fetch("resources").map do |reference|
          reference.slice("resource_key_hash", "lease_id", "fencing_token").transform_keys(&:to_sym)
        end
      }
    ).dig("result", "taskId")
    execute_task(task_id)
    task_id
  end
  @expired_predecessor_release_state = task_request("tasks/get", @expired_predecessor_release_task_id)
end

Then("the predecessor release is denied without affecting the successor") do
  outcome = @expired_predecessor_release_state.dig("result", "result", "structuredContent")
  assert_acceptance_equal("completed", @expired_predecessor_release_state.dig("result", "status"), "Release Task")
  assert_acceptance_equal(true, @expired_predecessor_release_state.dig("result", "result", "isError"), "Release error")
  assert_acceptance(%w[lease_set_expired lease_set_not_current].include?(outcome.dig("data", "code")), "Release denial")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseAcquired" ],
    lease_events(@expiry_path).map(&:type),
    "Successor lifecycle"
  )
end

When("the agent abandons the Attempt because its execution was interrupted") do
  @abandonment_arguments = {
    command_id: "cmd-cuc-attempt-abandon",
    actor: { kind: "agent", id: @release_agent_id },
    change_set_id: @release_change_set_id,
    work_item_id: @release_work_item_id,
    attempt_id: @release_attempt_id,
    reason: "The agent process was interrupted before a Candidate was produced."
  }
  response = call_tool(
    "attempt_abandon",
    @abandonment_arguments
  )
  @abandonment_task_id = response.dig("result", "taskId")
  assert_acceptance(
    @abandonment_task_id,
    "attempt_abandon did not return a Task handle: #{response.inspect}"
  )
  execute_task(@abandonment_task_id)
  @abandonment_task_state = task_request("tasks/get", @abandonment_task_id)
end

Then("the abandonment Task releases current fences and requeues the WorkItem") do
  result = @abandonment_task_state.dig("result", "result")
  payload = result.fetch("structuredContent")
  abandonment_events = event_store.read(
    streams.attempt(@release_attempt_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "AttemptAbandoned" ],
      maximum_count: 1,
      direction: :asc
    )
  )
  requeue_events = event_store.read(
    streams.work_item(@release_work_item_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "WorkItemRequeued" ],
      maximum_count: 1,
      direction: :asc
    )
  )

  assert_acceptance_equal("completed", @abandonment_task_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Abandonment error flag")
  assert_acceptance_equal("ok", payload.fetch("status"), "Abandonment outcome")
  assert_acceptance_equal(@release_attempt_id, payload.dig("data", "attempt_id"), "Receipt Attempt")
  assert_acceptance_equal(1, abandonment_events.length, "Attempt abandonment facts")
  assert_acceptance_equal(1, requeue_events.length, "WorkItem requeue facts")
  assert_acceptance_equal(
    @release_reservation.fetch("resources").map { _1.fetch("resource_key_hash") }.sort,
    abandonment_events.sole.data.fetch("released_leases").map { _1.fetch("resource_key_hash") }.sort,
    "Released abandonment fences"
  )
  assert_acceptance_equal(
    [],
    abandonment_events.sole.data.fetch("untouched_resource_key_hashes"),
    "Untouched abandonment fences"
  )
  @release_paths.each do |path|
    assert_acceptance_equal(
      [ "ResourceLeaseAcquired", "ResourceLeaseReleased" ],
      lease_events(path).map(&:type),
      "Abandoned lease lifecycle for #{path}"
    )
  end
  assert_acceptance_equal(1, command_events(@abandonment_arguments.fetch(:command_id)).length, "Command receipt")
end

When("the exact abandonment command is retried through another Task") do
  @abandonment_retry_task_id = call_tool(
    "attempt_abandon",
    @abandonment_arguments
  ).dig("result", "taskId")
  execute_task(@abandonment_retry_task_id)
  @abandonment_retry_task_state = task_request("tasks/get", @abandonment_retry_task_id)
end

Then("both abandonment Task handles expose one logical result") do
  assert_acceptance_equal(
    @abandonment_task_state.dig("result", "result"),
    @abandonment_retry_task_state.dig("result", "result"),
    "Abandonment replay result"
  )
  assert_acceptance_equal(
    1,
    command_events(@abandonment_arguments.fetch(:command_id)).length,
    "Abandonment command completions"
  )
  assert_acceptance_equal(
    1,
    event_store.read(
      streams.attempt(@release_attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "AttemptAbandoned" ],
        maximum_count: 1,
        direction: :asc
      )
    ).length,
    "Attempt abandonment lifecycle"
  )
end

When("the agent reacquires the requeued WorkItem as fresh Attempt {string}") do |attempt_id|
  @fresh_attempt_id = attempt_id
  @fresh_base_commit_oid = "b" * 40
  @fresh_acquisition_task_id = submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-attempt-reacquire",
    actor: { kind: "agent", id: @release_agent_id },
    change_set_id: @release_change_set_id,
    work_item_id: @release_work_item_id,
    attempt_id:,
    base_snapshots: [
      { repository_id: "billing", commit_oid: @fresh_base_commit_oid }
    ]
  )
  @fresh_acquisition_state = task_request("tasks/get", @fresh_acquisition_task_id)
end

Then("the fresh Attempt starts from a new base declaration while the old Attempt remains terminal") do
  result = @fresh_acquisition_state.dig("result", "result")
  fresh_events = attempt_events(@fresh_attempt_id)
  abandonment = event_store.read(
    streams.attempt(@release_attempt_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "AttemptAbandoned" ],
      maximum_count: 1,
      direction: :asc
    )
  ).sole
  current_work_item = event_store.read_grouped(
    streams.work_item(@release_work_item_id),
    Coordinator::Write::GroupedEventReadCriteria.new(
      event_types: [ "WorkItemAcquired", "WorkItemRequeued" ],
      direction: :desc
    )
  ).reverse.last

  assert_acceptance_equal(false, result.fetch("isError"), "Fresh acquisition error flag")
  assert_acceptance_equal(
    [ "AttemptAuthorized", "AttemptStarted" ],
    fresh_events.map(&:type),
    "Fresh Attempt lifecycle"
  )
  assert_acceptance_equal(
    @fresh_base_commit_oid,
    fresh_events.first.data.fetch("base_snapshots").sole.fetch("commit_oid"),
    "Fresh base snapshot"
  )
  assert_acceptance_equal(@release_attempt_id, abandonment.data.fetch("attempt_id"), "Terminal old Attempt")
  assert_acceptance_equal(@fresh_attempt_id, current_work_item.data.fetch("attempt_id"), "Current WorkItem Attempt")
end

When("the expired predecessor abandons its Attempt") do
  @superseded_abandonment_task_id = Timecop.freeze(@expiry_started_at + 32) do
    response = call_tool(
      "attempt_abandon",
      {
        command_id: "cmd-cuc-attempt-abandon-superseded",
        actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
        change_set_id: @lease_change_set_id,
        work_item_id: @expiry_predecessor.fetch(:work_item_id),
        attempt_id: @expiry_predecessor.fetch(:attempt_id),
        reason: "The predecessor lost its lease fence and is yielding the WorkItem."
      }
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "attempt_abandon did not return a Task handle: #{response.inspect}")
    execute_task(task_id)
    task_id
  end
  @superseded_abandonment_state = task_request("tasks/get", @superseded_abandonment_task_id)
end

Then("the abandonment requeues the predecessor and leaves the successor fence untouched") do
  result = @superseded_abandonment_state.dig("result", "result")
  abandonment = event_store.read(
    streams.attempt(@expiry_predecessor.fetch(:attempt_id)),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "AttemptAbandoned" ],
      maximum_count: 1,
      direction: :asc
    )
  ).sole
  requeue = event_store.read(
    streams.work_item(@expiry_predecessor.fetch(:work_item_id)),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "WorkItemRequeued" ],
      maximum_count: 1,
      direction: :asc
    )
  ).sole
  lifecycle = lease_events(@expiry_path)

  assert_acceptance_equal(false, result.fetch("isError"), "Superseded abandonment error flag")
  assert_acceptance_equal([], abandonment.data.fetch("released_leases"), "Released predecessor fences")
  assert_acceptance_equal(
    [ @expiry_predecessor_result.fetch("resources").sole.fetch("resource_key_hash") ],
    abandonment.data.fetch("untouched_resource_key_hashes"),
    "Untouched predecessor fences"
  )
  assert_acceptance_equal(@expiry_predecessor.fetch(:attempt_id), requeue.data.fetch("attempt_id"), "Requeued Attempt")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseAcquired" ],
    lifecycle.map(&:type),
    "Successor lifecycle"
  )
  assert_acceptance_equal(
    @expiry_successor.fetch(:attempt_id),
    lifecycle.last.data.fetch("attempt_id"),
    "Successor ownership"
  )
  assert_acceptance_equal(2, lifecycle.last.data.fetch("fencing_token"), "Successor fence")
end

Given(
  "agent {string} has attached Candidate {string} to active Attempt {string}"
) do |agent_id, candidate_id, attempt_id|
  @candidate_abandonment_coordination = prepare_candidate_coordination(
    prefix: "ABANDON",
    agent_id:,
    path: "app/candidate_abandon.rb",
    project_context: false
  )
  ids = @candidate_abandonment_coordination.fetch(:ids)
  assert_acceptance_equal(attempt_id, ids.fetch(:attempt_id), "Candidate-bearing Attempt")
  @candidate_abandonment_candidate_id = candidate_id
  arguments = candidate_arguments(
    @candidate_abandonment_coordination,
    candidate_id:,
    command_id: "cmd-cuc-candidate-abandon-submit",
    head_character: "e"
  )
  task_id = submit_candidate_task(arguments)
  state = candidate_task_state(task_id)
  assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Candidate setup")
end

When("the agent tries to abandon the Candidate-bearing Attempt") do
  coordination = @candidate_abandonment_coordination
  ids = coordination.fetch(:ids)
  @candidate_abandonment_command_id = "cmd-cuc-candidate-attempt-abandon"
  response = call_tool(
    "attempt_abandon",
    {
      command_id: @candidate_abandonment_command_id,
      actor: { kind: "agent", id: coordination.fetch(:agent_id) },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      reason: "The agent wants to discard work after checkpointing it."
    }
  )
  @candidate_abandonment_task_id = response.dig("result", "taskId")
  assert_acceptance(
    @candidate_abandonment_task_id,
    "attempt_abandon did not return a Task handle: #{response.inspect}"
  )
  execute_task(@candidate_abandonment_task_id)
  @candidate_abandonment_state = task_request("tasks/get", @candidate_abandonment_task_id)
end

Then("abandonment is denied without releasing leases or requeueing the WorkItem") do
  coordination = @candidate_abandonment_coordination
  ids = coordination.fetch(:ids)
  result = @candidate_abandonment_state.dig("result", "result")
  payload = result.fetch("structuredContent")
  attempt_terminal_events = event_store.read(
    streams.attempt(ids.fetch(:attempt_id)),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "CandidateAttachedToAttempt", "AttemptAbandoned" ],
      maximum_count: 2,
      direction: :asc
    )
  )
  requeue_events = event_store.read(
    streams.work_item(ids.fetch(:work_item_id)),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "WorkItemRequeued" ],
      maximum_count: 1,
      direction: :asc
    )
  )

  assert_acceptance_equal("completed", @candidate_abandonment_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(true, result.fetch("isError"), "Candidate abandonment error flag")
  assert_acceptance_equal("denied", payload.fetch("status"), "Candidate abandonment outcome")
  assert_acceptance_equal("attempt_not_active", payload.dig("data", "code"), "Candidate denial code")
  assert_acceptance_equal([ "CandidateAttachedToAttempt" ], attempt_terminal_events.map(&:type), "Attempt facts")
  assert_acceptance_equal([], requeue_events, "WorkItem requeue facts")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired" ],
    lease_events(coordination.fetch(:path)).map(&:type),
    "Candidate lease lifecycle"
  )
  assert_acceptance_equal([], command_events(@candidate_abandonment_command_id), "Denied command receipt")
end
