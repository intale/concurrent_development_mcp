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
      repository_id: acceptance_repository_id,
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
  @lease_participants.each { await_work_item_ready(_1.fetch(:work_item_id)) }

  @lease_participants.each do |participant|
    submit_and_execute(
      "work_item_acquire",
      command_id: "cmd-cuc-lse-acquire-#{participant.fetch(:attempt_id)}",
      actor: { kind: "agent", id: participant.fetch(:agent_id) },
      change_set_id:,
      work_item_id: participant.fetch(:work_item_id),
      attempt_id: participant.fetch(:attempt_id),
      base_snapshots: [
        { repository_id: acceptance_repository_id, commit_oid: "a" * 40 }
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
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [
        resource_target(
          kind: "file",
          path: participant.fetch(:unique_path),
          actor_id: participant.fetch(:agent_id)
        ),
        resource_target(kind: "file", path: shared_path, actor_id: participant.fetch(:agent_id))
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
    repository_id: acceptance_repository_id,
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
  await_work_item_ready(@expansion_work_item_id)
  submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-expand-acquire",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @expansion_work_item_id,
    attempt_id:,
    base_snapshots: [ { repository_id: acceptance_repository_id, commit_oid: "a" * 40 } ]
  )
  reservation_task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-expand-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @expansion_work_item_id,
    attempt_id:,
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path: initial_path, actor_id: agent_id) ],
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
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [ resource_target(kind: "file", path: additional_path, actor_id: @expansion_agent_id) ]
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
  @expanded_context = await_read_model("Write-set expansion to become available") do
    response = call_tool("coord_context", { attempt_id: @expansion_attempt_id })
    resources = response.dig(
      "result", "structuredContent", "data", "context", "attempts", 0, "write_set", "resources"
    ) || []
    [ resources.any? { _1.fetch("resource_path") == @expansion_additional_path }, response ]
  end
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
    repository_id: acceptance_repository_id,
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
  await_work_item_ready(@renewal_work_item_id)
  submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-renew-acquire",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @renewal_work_item_id,
    attempt_id:,
    base_snapshots: [ { repository_id: acceptance_repository_id, commit_oid: "a" * 40 } ]
  )
  reservation_task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-renew-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @renewal_work_item_id,
    attempt_id:,
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: @renewal_paths.map { resource_target(kind: "file", path: _1, actor_id: agent_id) },
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
          resource_id: reference.fetch("resource_id"),
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
    reference.values_at("resource_id", "lease_id", "fencing_token")
  end
  after_refs = data.fetch("resources").map do |reference|
    reference.values_at("resource_id", "lease_id", "fencing_token")
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
  @renewed_context = await_read_model("Write-set renewal to become available") do
    response = call_tool("coord_context", { attempt_id: @renewal_attempt_id })
    observed = response.dig(
      "result", "structuredContent", "data", "context", "attempts", 0, "write_set", "expires_at"
    )
    [ observed == @renewal_result.fetch("expires_at"), response ]
  end
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
    repository_id: acceptance_repository_id,
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
  await_work_item_ready(@release_work_item_id)
  submit_and_execute(
    "work_item_acquire",
    command_id: "cmd-cuc-release-acquire",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @release_work_item_id,
    attempt_id:,
    base_snapshots: [ { repository_id: acceptance_repository_id, commit_oid: "a" * 40 } ]
  )
  reservation_task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-release-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @release_work_item_id,
    attempt_id:,
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: @release_paths.map { resource_target(kind: "file", path: _1, actor_id: agent_id) },
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
          resource_id: reference.fetch("resource_id"),
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
    reference.values_at("resource_id", "lease_id", "fencing_token")
  end
  after_refs = data.fetch("resources").map do |reference|
    reference.values_at("resource_id", "lease_id", "fencing_token")
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
  @released_context = await_read_model("Write-set release to become available") do
    response = call_tool("coord_context", { attempt_id: @release_attempt_id })
    observed = response.dig(
      "result", "structuredContent", "data", "context", "attempts", 0, "write_set", "released_at"
    )
    [ observed == @release_result.fetch("released_at"), response ]
  end
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
  "agent {string} reserves {string} for {int} seconds"
) do |agent_id, path, duration|
  @expiry_predecessor = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  assert_acceptance(@expiry_predecessor, "Unknown predecessor agent #{agent_id}")

  @expiry_path = path
  @expiry_predecessor_command_id = "cmd-cuc-expiry-predecessor"
  @expiry_predecessor_task_id = call_tool(
    "write_set_reserve",
    {
      command_id: @expiry_predecessor_command_id,
      actor: { kind: "agent", id: agent_id },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_predecessor.fetch(:work_item_id),
      attempt_id: @expiry_predecessor.fetch(:attempt_id),
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [ resource_target(kind: "file", path:, actor_id: agent_id) ],
      lease_duration_seconds: duration
    }
  ).dig("result", "taskId")
  execute_task(@expiry_predecessor_task_id)
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

  predecessor_expiry = Time.iso8601(@expiry_predecessor_result.fetch("expires_at"))
  eventually("Predecessor lease to elapse", timeout_seconds: 35) do
    now = Time.now.utc
    [ now >= predecessor_expiry, now.iso8601(6) ]
  end
  @expiry_successor_task_id = call_tool(
    "write_set_reserve",
    {
      command_id: "cmd-cuc-expiry-successor",
      actor: { kind: "agent", id: agent_id },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_successor.fetch(:work_item_id),
      attempt_id: @expiry_successor.fetch(:attempt_id),
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [ resource_target(kind: "file", path: @expiry_path, actor_id: agent_id) ],
      lease_duration_seconds: 300
    }
  ).dig("result", "taskId")
  execute_task(@expiry_successor_task_id)
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
  perform_scheduled_lease_expiry(@expiry_source)
end

Then("the timer is superseded and cannot affect the successor") do
  process_step = process_step_event(
    source_event: @expiry_source,
    process_name: "lease-expiry-policy",
    step_name: "expire-resource-lease",
    subject_kind: "resource-lease",
    subject_id: @expiry_source.data.fetch("lease_id")
  )
  assert_acceptance(process_step, "The superseded timer has no persisted process step")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseAcquired" ],
    lease_events(@expiry_path).map(&:type),
    "Lease lifecycle after the old timer"
  )
  assert_acceptance_equal(
    [],
    command_events(process_step.data.fetch("target_command_id")),
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
  predecessor = payload.dig("data", "context", "attempts").find do |attempt|
    attempt.fetch("attempt_id") == @expiry_predecessor.fetch(:attempt_id)
  end
  write_set = predecessor&.fetch("write_set")

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
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [
        resource_target(
          kind: "file",
          path: participant.fetch(:unique_path),
          actor_id: participant.fetch(:agent_id)
        )
      ],
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
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [ resource_target(kind: "file", path:, actor_id: participant.fetch(:agent_id)) ],
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
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path:, actor_id: agent_id) ],
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
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path:, actor_id: agent_id) ],
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
  @renewed_predecessor_task_id = call_tool(
    "lease_renew",
    {
      command_id: "cmd-cuc-renew-predecessor",
      actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_predecessor.fetch(:work_item_id),
      attempt_id: @expiry_predecessor.fetch(:attempt_id),
      lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
      leases: @expiry_predecessor_result.fetch("resources").map do |reference|
        reference.slice("resource_id", "lease_id", "fencing_token").transform_keys(&:to_sym)
      end,
      lease_duration_seconds: 60
    }
  ).dig("result", "taskId")
  execute_task(@renewed_predecessor_task_id)
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
  old_expiry = Time.iso8601(@expiry_predecessor_result.fetch("expires_at"))
  eventually("Original lease deadline to elapse", timeout_seconds: 35) do
    now = Time.now.utc
    [ now >= old_expiry, now.iso8601(6) ]
  end
  @renewal_contender_task_id = call_tool(
    "write_set_reserve",
    {
      command_id: "cmd-cuc-renew-contender",
      actor: { kind: "agent", id: agent_id },
      change_set_id: @lease_change_set_id,
      work_item_id: participant.fetch(:work_item_id),
      attempt_id: participant.fetch(:attempt_id),
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [ resource_target(kind: "file", path: @expiry_path, actor_id: agent_id) ],
      lease_duration_seconds: 300
    }
  ).dig("result", "taskId")
  execute_task(@renewal_contender_task_id)
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
      reference.slice("resource_id", "lease_id", "fencing_token").transform_keys(&:to_sym)
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
  @predecessor_release_task_id = call_tool(
    "lease_release",
    {
      command_id: "cmd-cuc-release-predecessor",
      actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_predecessor.fetch(:work_item_id),
      attempt_id: @expiry_predecessor.fetch(:attempt_id),
      lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
      leases: @expiry_predecessor_result.fetch("resources").map do |reference|
        reference.slice("resource_id", "lease_id", "fencing_token").transform_keys(&:to_sym)
      end
    }
  ).dig("result", "taskId")
  execute_task(@predecessor_release_task_id)
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
  task_id = submit_and_execute(
    "write_set_reserve",
    command_id: "cmd-cuc-release-successor",
    actor: { kind: "agent", id: agent_id },
    change_set_id: @lease_change_set_id,
    work_item_id: participant.fetch(:work_item_id),
    attempt_id: participant.fetch(:attempt_id),
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path: @expiry_path, actor_id: agent_id) ],
    lease_duration_seconds: 300
  )
  @successor_result = task_request("tasks/get", task_id).dig(
    "result", "result", "structuredContent", "data"
  )
end

When("the expired predecessor tries to renew its old fence") do
  @expired_predecessor_renewal_task_id = call_tool(
    "lease_renew",
    {
      command_id: "cmd-cuc-expired-predecessor-renew",
      actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_predecessor.fetch(:work_item_id),
      attempt_id: @expiry_predecessor.fetch(:attempt_id),
      lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
      leases: @expiry_predecessor_result.fetch("resources").map do |reference|
        reference.slice("resource_id", "lease_id", "fencing_token").transform_keys(&:to_sym)
      end,
      lease_duration_seconds: 300
    }
  ).dig("result", "taskId")
  execute_task(@expired_predecessor_renewal_task_id)
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
  @expired_predecessor_release_task_id = call_tool(
    "lease_release",
    {
      command_id: "cmd-cuc-expired-predecessor-release",
      actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_predecessor.fetch(:work_item_id),
      attempt_id: @expiry_predecessor.fetch(:attempt_id),
      lease_set_id: @expiry_predecessor_result.fetch("lease_set_id"),
      leases: @expiry_predecessor_result.fetch("resources").map do |reference|
        reference.slice("resource_id", "lease_id", "fencing_token").transform_keys(&:to_sym)
      end
    }
  ).dig("result", "taskId")
  execute_task(@expired_predecessor_release_task_id)
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
    @release_reservation.fetch("resources").map { _1.fetch("resource_id") }.sort,
    abandonment_events.sole.data.fetch("released_leases").map { _1.fetch("resource_id") }.sort,
    "Released abandonment fences"
  )
  assert_acceptance_equal(
    [],
    abandonment_events.sole.data.fetch("untouched_resource_ids"),
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
      { repository_id: acceptance_repository_id, commit_oid: @fresh_base_commit_oid }
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
  @superseded_abandonment_task_id = response.dig("result", "taskId")
  assert_acceptance(
    @superseded_abandonment_task_id,
    "attempt_abandon did not return a Task handle: #{response.inspect}"
  )
  execute_task(@superseded_abandonment_task_id)
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
    [ @expiry_predecessor_result.fetch("resources").sole.fetch("resource_id") ],
    abandonment.data.fetch("untouched_resource_ids"),
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
  "agent {string} has attached {string} Candidate {string} to active Attempt {string}"
) do |agent_id, checkpoint_kind, candidate_id, attempt_id|
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
  arguments[:checkpoint_kind] = checkpoint_kind
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

Then("the checkpoint remains recorded while the Attempt is abandoned and requeued") do
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
  assert_acceptance_equal(false, result.fetch("isError"), "Intermediate abandonment error flag")
  assert_acceptance_equal("ok", payload.fetch("status"), "Intermediate abandonment outcome")
  assert_acceptance_equal(
    [ "CandidateAttachedToAttempt", "AttemptAbandoned" ],
    attempt_terminal_events.map(&:type),
    "Attempt facts"
  )
  assert_acceptance_equal([ "WorkItemRequeued" ], requeue_events.map(&:type), "WorkItem requeue facts")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseReleased" ],
    lease_events(coordination.fetch(:path)).map(&:type),
    "Intermediate Candidate lease lifecycle"
  )
  assert_acceptance_equal(1, command_events(@candidate_abandonment_command_id).length, "Command receipt")
end

module HierarchicalWriteSetAcceptance
  def prepare_live_hierarchical_attempts(change_set_id)
    start_live_subscriptions
    suffix = change_set_id.downcase
    @hierarchical_change_set_id = change_set_id
    @hierarchical_participants = [
      { agent_id: "agent-a", work_item_id: "W-AUD-LSE-A", attempt_id: "A-AUD-LSE-A" },
      { agent_id: "agent-b", work_item_id: "W-AUD-LSE-B", attempt_id: "A-AUD-LSE-B" }
    ]

    submit_and_await(
      "change_set_create",
      command_id: "#{suffix}.create",
      actor: { kind: "agent", id: "planner" },
      change_set_id:,
      goal: "Coordinate Git hierarchy leases",
      acceptance_criteria: [ "File and directory overlap has one active owner" ]
    )
    @hierarchical_participants.each do |participant|
      submit_and_await(
        "work_item_create",
        command_id: "#{suffix}.create.#{participant.fetch(:work_item_id)}",
        actor: { kind: "agent", id: "planner" },
        change_set_id:,
        work_item_id: participant.fetch(:work_item_id),
        repository_id: acceptance_repository_id,
        goal: "Edit a Git resource",
        acceptance_criteria: [ "The resource is exclusively coordinated" ]
      )
    end
    submit_and_await(
      "change_set_activate",
      command_id: "#{suffix}.activate",
      actor: { kind: "agent", id: "planner" },
      change_set_id:
    )

    @hierarchical_participants.each do |participant|
      eventually("#{participant.fetch(:work_item_id)} to become ready") do
        events = work_item_events(participant.fetch(:work_item_id))
        [ events.any? { _1.type == "WorkItemMadeReady" }, events.map(&:type) ]
      end
      task_id = submit_and_await(
        "work_item_acquire",
        command_id: "#{suffix}.acquire.#{participant.fetch(:attempt_id)}",
        actor: { kind: "agent", id: participant.fetch(:agent_id) },
        change_set_id:,
        work_item_id: participant.fetch(:work_item_id),
        attempt_id: participant.fetch(:attempt_id),
        base_snapshots: [
          { repository_id: acceptance_repository_id, commit_oid: "a" * 40 }
        ]
      )
      state = task_request("tasks/get", task_id)
      assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Attempt acquisition")
    end
  end

  def submit_live_hierarchical_reservation(
    agent_id:,
    kind:,
    path:,
    command_suffix: nil,
    command_id: nil,
    await_terminal: true
  )
    participant = @hierarchical_participants.find { _1.fetch(:agent_id) == agent_id }
    assert_acceptance(participant, "Unknown hierarchy participant #{agent_id}")
    command_id ||= "#{@hierarchical_change_set_id.downcase}.reserve.#{command_suffix}"
    response = call_tool(
      "write_set_reserve",
      {
        command_id:,
        actor: { kind: "agent", id: agent_id },
        change_set_id: @hierarchical_change_set_id,
        work_item_id: participant.fetch(:work_item_id),
        attempt_id: participant.fetch(:attempt_id),
        repository_id: acceptance_repository_id,
        base_commit_oid: "a" * 40,
        resources: [
          resource_target(
            kind:,
            path:,
            client_id: agent_id,
            actor_id: agent_id
          )
        ],
        lease_duration_seconds: 300
      },
      client_id: agent_id
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "write_set_reserve did not return a Task: #{response.inspect}")

    {
      agent_id:,
      kind:,
      path:,
      command_id:,
      task_id:,
      client_id: agent_id,
      state: await_terminal ? await_task_terminal(task_id, client_id: agent_id) : nil
    }
  end

  def distinct_lane_command_ids(prefix)
    lane = Coordinator::Write::Tasks::ExecutionLane.new
    by_lane = {}
    32.times do |index|
      command_id = "#{prefix}.#{index}"
      by_lane[lane.index(command_id)] ||= command_id
      break if by_lane.length == Coordinator::Write::Tasks::ExecutionLane::COUNT
    end
    assert_acceptance_equal(
      Coordinator::Write::Tasks::ExecutionLane::COUNT,
      by_lane.length,
      "Distinct Task execution lanes"
    )
    by_lane.sort.map(&:last)
  end

  def hierarchical_lease_events(kind, path)
    resource_id = (@acceptance_resource_ids || {}).fetch(
      [ acceptance_repository_id, kind, path ]
    )
    event_store.read(
      streams.resource_lease(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          ResourceLeaseAcquired
          ResourceLeaseRenewed
          ResourceLeaseReleased
          ResourceLeaseExpired
        ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def hierarchical_outcome(reservation)
    reservation.dig(:state, "result", "result", "structuredContent")
  end
end

World(HierarchicalWriteSetAcceptance)

Given(
  "two independent MCP agents have live active Attempts in ChangeSet {string}"
) do |change_set_id|
  prepare_live_hierarchical_attempts(change_set_id)
  @hierarchical_reservations = []
end

When(
  "agent {string} reserves {word} {string} through a public Task"
) do |agent_id, kind, path|
  @hierarchical_reservations << submit_live_hierarchical_reservation(
    agent_id:,
    kind:,
    path:,
    command_suffix: @hierarchical_reservations.length + 1
  )
end

When(
  "agent {string} tries to resolve {word} {string} for leasing"
) do |agent_id, kind, path|
  task_id = submit_and_await(
    "resource_resolve",
    client_id: agent_id,
    command_id: "#{@hierarchical_change_set_id.downcase}.resolve.alternative-kind",
    actor: { kind: "agent", id: agent_id },
    repository_id: acceptance_repository_id,
    kind:,
    path:
  )
  @alternative_kind_resolution = {
    kind:,
    path:,
    state: task_request("tasks/get", task_id, client_id: agent_id)
  }
end

Then("the first hierarchical reservation succeeds and the alternative kind is denied") do
  reservation = @hierarchical_reservations.sole
  resolution = @alternative_kind_resolution.fetch(:state).dig("result", "result")

  assert_acceptance_equal("completed", reservation.dig(:state, "result", "status"), "Reservation Task")
  assert_acceptance_equal("ok", hierarchical_outcome(reservation).fetch("status"), "Reservation outcome")
  assert_acceptance_equal(true, resolution.fetch("isError"), "Alternative-kind error flag")
  assert_acceptance_equal(
    "resource_path_conflict",
    resolution.dig("structuredContent", "data", "code"),
    "Alternative-kind denial"
  )
end

Then("only the current file resource has a durable lease acquisition") do
  reservation = @hierarchical_reservations.sole
  assert_acceptance_equal("file", reservation.fetch(:kind), "Current Resource kind")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired" ],
    hierarchical_lease_events("file", reservation.fetch(:path)).map(&:type),
    "Current Resource lifecycle"
  )
end

Then("the first hierarchical reservation succeeds and the second completes busy") do
  first, second = @hierarchical_reservations
  assert_acceptance_equal("completed", first.dig(:state, "result", "status"), "First Task status")
  assert_acceptance_equal("ok", hierarchical_outcome(first).fetch("status"), "First reservation")
  assert_acceptance_equal("completed", second.dig(:state, "result", "status"), "Second Task status")
  assert_acceptance_equal("busy", hierarchical_outcome(second).fetch("status"), "Second reservation")
  assert_acceptance_equal(
    first.fetch(:agent_id),
    hierarchical_outcome(second).dig("data", "details", "owner_agent_id"),
    "Blocking owner"
  )
end

Then("only the {word} resource has a durable lease acquisition") do |winning_kind|
  winning = @hierarchical_reservations.first
  losing = @hierarchical_reservations.last
  assert_acceptance_equal(winning_kind, winning.fetch(:kind), "Winning resource kind")
  assert_acceptance_equal(
    [ "ResourceLeaseAcquired" ],
    hierarchical_lease_events(winning.fetch(:kind), winning.fetch(:path)).map(&:type),
    "Winning lifecycle"
  )
  assert_acceptance_equal(
    [],
    hierarchical_lease_events(losing.fetch(:kind), losing.fetch(:path)),
    "Losing lifecycle"
  )
end

When("both agents submit public reservation Tasks for disjoint resources and reach the reservation decision boundary") do
  command_ids = distinct_lane_command_ids("#{@hierarchical_change_set_id.downcase}.reserve.disjoint")
  install_contention_barrier(operation: "write_set_reserve", command_ids:)
  prepare_mcp_clients("agent-a", "agent-b")
  requests = [
    { agent_id: "agent-a", kind: "directory", path: "app/models", command_id: command_ids.fetch(0) },
    {
      agent_id: "agent-b",
      kind: "file",
      path: "spec/services/user_spec.rb",
      command_id: command_ids.fetch(1)
    }
  ]
  @hierarchical_reservations = requests.map do |arguments|
    Thread.new do
      submit_live_hierarchical_reservation(**arguments, await_terminal: false)
    end
  end.map(&:value)
  await_contention_evidence
end

Then("both reservation operations have deterministic contention evidence") do
  assert_acceptance_equal(2, @contention_evidence.length, "Reservation boundary arrivals")
  assert_acceptance_equal(
    @hierarchical_reservations.map { _1.fetch(:command_id) }.sort,
    @contention_evidence.map { _1.fetch(:command_id) }.sort,
    "Reservation boundary commands"
  )
  assert_acceptance_equal(2, @contention_evidence.map { _1.fetch(:thread_id) }.uniq.length, "Worker threads")
  assert_acceptance_equal([ 0, 1 ], @contention_evidence.map { _1.fetch(:worker_lane) }.sort, "Worker lanes")
end

When("the reservation decision boundary is released") do
  release_contention_barrier
  @hierarchical_reservations.each do |reservation|
    reservation[:state] = await_task_terminal(
      reservation.fetch(:task_id),
      client_id: reservation.fetch(:client_id)
    )
  end
end

Then("both hierarchical reservation Tasks complete successfully") do
  @hierarchical_reservations.each do |reservation|
    assert_acceptance_equal("completed", reservation.dig(:state, "result", "status"), "Task status")
    assert_acceptance_equal("ok", hierarchical_outcome(reservation).fetch("status"), "Reservation status")
    assert_acceptance_equal(
      [ "ResourceLeaseAcquired" ],
      hierarchical_lease_events(reservation.fetch(:kind), reservation.fetch(:path)).map(&:type),
      "Resource lifecycle"
    )
  end
end

When(
  "agent {string} submits literal resource path {string} through public MCP"
) do |agent_id, path|
  @literal_resource_path = path
  @literal_path_command_id = "#{@hierarchical_change_set_id.downcase}.reserve.literal-path"
  @literal_path_response = call_tool(
    "resource_resolve",
    {
      command_id: @literal_path_command_id,
      actor: { kind: "agent", id: agent_id },
      repository_id: acceptance_repository_id,
      kind: "file",
      path:
    },
    expected_status: 400
  )
end

Then("MCP rejects the unsupported path before allocating a Task") do
  error = @literal_path_response.fetch("error")
  assert_acceptance_equal(-32_602, error.fetch("code"), "JSON-RPC error")
  assert_acceptance_equal("invalid_input", error.dig("data", "code"), "Literal path error")
  assert_acceptance_equal([], task_events_for_command(@literal_path_command_id), "Task facts")
end

Then("no lease is stored for either path spelling") do
  assert_acceptance_equal([], command_events(@literal_path_command_id), "Command facts")
  lease = PgEventstore.client.read(
    PgEventstore::Stream.all_stream,
    options: {
      direction: :asc,
      max_count: 1,
      filter: { event_types: [ { type: "ResourceLeaseAcquired" } ] }
    }
  )
  assert_acceptance_equal([], lease, "Lease facts")
end

When(
  "agent {string} reserves expiring file {string} through a public Task"
) do |agent_id, path|
  participant = @hierarchical_participants.find { _1.fetch(:agent_id) == agent_id }
  assert_acceptance(participant, "Unknown expiry participant #{agent_id}")
  @system_identity_path = path

  task_id = submit_and_await(
    "write_set_reserve",
    command_id: "cs-aud-lse-expiry-id.reserve.predecessor",
    actor: { kind: "agent", id: agent_id },
    change_set_id: @hierarchical_change_set_id,
    work_item_id: participant.fetch(:work_item_id),
    attempt_id: participant.fetch(:attempt_id),
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path:, actor_id: agent_id) ],
    lease_duration_seconds: 30
  )
  state = task_request("tasks/get", task_id)
  assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Predecessor reservation")

  @system_identity_source = hierarchical_lease_events("file", path).sole
end

When("a public client uses the acquisition event ID for an unrelated mutation") do
  @public_collision_command_id = @system_identity_source.id
  task_id = submit_and_await(
    "change_set_create",
    command_id: @public_collision_command_id,
    actor: { kind: "agent", id: "agent-a" },
    change_set_id: "CS-AUD-LSE-PUBLIC-COLLISION",
    goal: "Prove public and internal command identities cannot collide",
    acceptance_criteria: [ "The unrelated public command remains independently replayable" ]
  )
  state = task_request("tasks/get", task_id)
  assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Public collision command")
end

When("the real lease-expiry job handles the due source") do
  deadline = Time.iso8601(@system_identity_source.data.fetch("expires_at"))

  eventually("the real lease deadline", timeout_seconds: 35) do
    observed_at = Time.now.utc
    [ observed_at >= deadline, observed_at ]
  end
  perform_scheduled_lease_expiry(@system_identity_source)
  @lease_expiry_process_step = process_step_event(
    source_event: @system_identity_source,
    process_name: "lease-expiry-policy",
    step_name: "expire-resource-lease",
    subject_kind: "resource-lease",
    subject_id: @system_identity_source.data.fetch("lease_id")
  )
  assert_acceptance(@lease_expiry_process_step, "Lease expiry has no persisted process step")
  @internal_expiry_command_id = @lease_expiry_process_step.data.fetch("target_command_id")
end

Then("the lease expires under a distinct deterministic internal command") do
  lifecycle = hierarchical_lease_events("file", @system_identity_path)
  acquisition, expiration = lifecycle

  assert_acceptance_equal(
    [ "ResourceLeaseAcquired", "ResourceLeaseExpired" ],
    lifecycle.map(&:type),
    "Expired lifecycle"
  )
  assert_acceptance(
    Coordinator::Shared::Types::UUID_V7_PATTERN.match?(@internal_expiry_command_id),
    "Internal command identity is not UUIDv7"
  )
  assert_acceptance(@internal_expiry_command_id != @public_collision_command_id, "Command namespaces collided")
  assert_acceptance_equal(@lease_expiry_process_step.id, expiration.causation_id, "Expiry causation")
  assert_acceptance_equal(acquisition.correlation_id, expiration.correlation_id, "Expiry correlation")
  assert_acceptance_equal(
    @internal_expiry_command_id,
    expiration.metadata.fetch("command_id"),
    "Expiry command metadata"
  )
  assert_acceptance_equal(1, command_events(@public_collision_command_id).length, "Public completion")
  assert_acceptance_equal(1, command_events(@internal_expiry_command_id).length, "Internal completion")
end

When("agent {string} reserves the expired file through a public Task") do |agent_id|
  participant = @hierarchical_participants.find { _1.fetch(:agent_id) == agent_id }
  @system_identity_successor_task_id = submit_and_await(
    "write_set_reserve",
    command_id: "cs-aud-lse-expiry-id.reserve.successor",
    actor: { kind: "agent", id: agent_id },
    change_set_id: @hierarchical_change_set_id,
    work_item_id: participant.fetch(:work_item_id),
    attempt_id: participant.fetch(:attempt_id),
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path: @system_identity_path, actor_id: agent_id) ],
    lease_duration_seconds: 300
  )
  @system_identity_successor_state = task_request("tasks/get", @system_identity_successor_task_id)
end

Then("the successor receives a higher fencing token") do
  outcome = @system_identity_successor_state.dig("result", "result", "structuredContent")
  assert_acceptance_equal("ok", outcome.fetch("status"), "Successor reservation")
  assert_acceptance_equal(
    2,
    outcome.dig("data", "resources").sole.fetch("fencing_token"),
    "Successor fencing token"
  )
  assert_acceptance_equal(
    [ 1, 1, 2 ],
    hierarchical_lease_events("file", @system_identity_path).map { _1.data.fetch("fencing_token") },
    "Lifecycle fencing history"
  )
end

When("a public client submits a command in the reserved internal namespace") do
  @reserved_public_command_id = "internal:lease-expiry:v1:client-supplied"
  @reserved_public_response = call_tool(
    "change_set_create",
    {
      command_id: @reserved_public_command_id,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-AUD-LSE-INTERNAL-NAMESPACE",
      goal: "This public request must not allocate a Task",
      acceptance_criteria: [ "The internal namespace remains system-owned" ]
    }
  )
end

Then("MCP rejects the reserved command ID before allocating a Task") do
  result = @reserved_public_response.fetch("result")
  assert_acceptance_equal("complete", result.fetch("resultType"), "Immediate result type")
  assert_acceptance_equal(true, result.fetch("isError"), "Reserved command-ID error flag")
  assert_acceptance_equal([], task_events_for_command(@reserved_public_command_id), "Task facts")
  assert_acceptance_equal([], command_events(@reserved_public_command_id), "Command facts")
end

class ResourceBoundaryRolloverGate
  EVENT_NAME = "coordinator.command_boundary"

  def initialize(reservation_command_id:)
    @reservation_command_id = reservation_command_id
    @mutex = Thread::Mutex.new
    @condition = Thread::ConditionVariable.new
    @arrivals = {}
    @released = false
    @subscriber = ActiveSupport::Notifications.subscribe(EVENT_NAME) do |_name, _start, _finish, _id, payload|
      role = role_for(payload)
      arrive(role, payload) if role
    end
  end

  def wait(timeout_seconds: 120)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
    @mutex.synchronize do
      until @arrivals.keys.sort == %i[reservation rollover]
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise timeout_error if remaining <= 0

        @condition.wait(@mutex, remaining)
      end
      @arrivals.transform_values(&:dup).freeze
    end
  end

  def release
    @mutex.synchronize do
      @released = true
      @condition.broadcast
    end
  end

  def close
    release
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  private

  def role_for(payload)
    return unless payload.fetch(:operation).to_s == "resource_boundary_dcb"

    command_id = payload.fetch(:command_id).to_s
    return :reservation if command_id == @reservation_command_id
    :rollover if Coordinator::Shared::Types::UUID_V7_PATTERN.match?(command_id)
  end

  def arrive(role, payload)
    @mutex.synchronize do
      @arrivals[role] ||= payload.slice(:command_id, :event_id, :event_ids, :source_event_id).freeze
      @condition.broadcast
      @condition.wait(@mutex) until @released
    end
  end

  def timeout_error
    missing = %i[reservation rollover] - @arrivals.keys
    "Timed out waiting for resource-boundary contention; missing arrivals: #{missing.inspect}"
  end
end

module ResourceBoundaryRolloverAcceptance
  ROLLOVER_CHANGE_SET_ID = "CS-AUD2-RESOURCE-ROLLOVER"
  OWNER = {
    agent_id: "rollover-owner",
    work_item_id: "W-AUD2-ROLLOVER-A",
    attempt_id: "A-AUD2-ROLLOVER-A"
  }.freeze
  CONTENDER = {
    agent_id: "rollover-contender",
    work_item_id: "W-AUD2-ROLLOVER-B",
    attempt_id: "A-AUD2-ROLLOVER-B"
  }.freeze

  def prepare_rollover_attempts
    prepare_mcp_clients(OWNER.fetch(:agent_id), CONTENDER.fetch(:agent_id))
    submit_and_execute(
      "change_set_create",
      command_id: "audit2-rollover.create",
      actor: { kind: "agent", id: "planner" },
      change_set_id: ROLLOVER_CHANGE_SET_ID,
      goal: "Keep hot resource boundaries available",
      acceptance_criteria: [ "Rollover preserves authoritative lease decisions" ]
    )
    [ OWNER, CONTENDER ].each do |participant|
      submit_and_execute(
        "work_item_create",
        command_id: "audit2-rollover.create.#{participant.fetch(:work_item_id)}",
        actor: { kind: "agent", id: "planner" },
        change_set_id: ROLLOVER_CHANGE_SET_ID,
        work_item_id: participant.fetch(:work_item_id),
        repository_id: acceptance_repository_id,
        goal: "Coordinate #{participant.fetch(:agent_id)}",
        acceptance_criteria: [ "The lease decision is serialized" ]
      )
    end
    submit_and_execute(
      "change_set_activate",
      command_id: "audit2-rollover.activate",
      actor: { kind: "agent", id: "planner" },
      change_set_id: ROLLOVER_CHANGE_SET_ID
    )
    [ OWNER, CONTENDER ].each { await_work_item_ready(_1.fetch(:work_item_id)) }
    [ OWNER, CONTENDER ].each do |participant|
      submit_and_execute(
        "work_item_acquire",
        client_id: participant.fetch(:agent_id),
        command_id: "audit2-rollover.acquire.#{participant.fetch(:attempt_id)}",
        actor: { kind: "agent", id: participant.fetch(:agent_id) },
        change_set_id: ROLLOVER_CHANGE_SET_ID,
        work_item_id: participant.fetch(:work_item_id),
        attempt_id: participant.fetch(:attempt_id),
        base_snapshots: [ { repository_id: acceptance_repository_id, commit_oid: "a" * 40 } ]
      )
    end
  end

  def reserve_rollover_resources(resources)
    targets = resources.map do |resource|
      resource_target(
        kind: resource.fetch(:kind),
        path: resource.fetch(:path),
        client_id: OWNER.fetch(:agent_id),
        actor_id: OWNER.fetch(:agent_id)
      )
    end
    task_id = submit_and_execute(
      "write_set_reserve",
      client_id: OWNER.fetch(:agent_id),
      command_id: "audit2-rollover.reserve.owner",
      actor: { kind: "agent", id: OWNER.fetch(:agent_id) },
      change_set_id: ROLLOVER_CHANGE_SET_ID,
      work_item_id: OWNER.fetch(:work_item_id),
      attempt_id: OWNER.fetch(:attempt_id),
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: targets,
      lease_duration_seconds: 600
    )
    successful_rollover_task_data(task_id, client_id: OWNER.fetch(:agent_id))
  end

  def renew_rollover_resources(receipt, count:)
    count.times.reduce(receipt) do |current, _index|
      @rollover_renewal_sequence = @rollover_renewal_sequence.to_i + 1
      task_id = submit_and_execute(
        "lease_renew",
        client_id: OWNER.fetch(:agent_id),
        command_id: "audit2-rollover.renew.#{@rollover_renewal_sequence}",
        actor: { kind: "agent", id: OWNER.fetch(:agent_id) },
        change_set_id: ROLLOVER_CHANGE_SET_ID,
        work_item_id: OWNER.fetch(:work_item_id),
        attempt_id: OWNER.fetch(:attempt_id),
        lease_set_id: current.fetch("lease_set_id"),
        leases: lease_observations(current),
        lease_duration_seconds: 600 + (@rollover_renewal_sequence * 60)
      )
      successful_rollover_task_data(task_id, client_id: OWNER.fetch(:agent_id))
    end
  end

  def expand_rollover_resources(receipt, resources:)
    targets = resources.map do |resource|
      resource_target(
        kind: resource.fetch(:kind),
        path: resource.fetch(:path),
        client_id: OWNER.fetch(:agent_id),
        actor_id: OWNER.fetch(:agent_id)
      )
    end
    task_id = submit_and_execute(
      "write_set_expand",
      client_id: OWNER.fetch(:agent_id),
      command_id: "audit2-rollover.expand.owner",
      actor: { kind: "agent", id: OWNER.fetch(:agent_id) },
      change_set_id: ROLLOVER_CHANGE_SET_ID,
      work_item_id: OWNER.fetch(:work_item_id),
      attempt_id: OWNER.fetch(:attempt_id),
      lease_set_id: receipt.fetch("lease_set_id"),
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: targets
    )
    expansion = successful_rollover_task_data(task_id, client_id: OWNER.fetch(:agent_id))
    all_resources = (receipt.fetch("resources") + expansion.fetch("added_resources"))
      .sort_by { _1.fetch("resource_id").b }
    receipt.merge("resources" => all_resources, "expires_at" => expansion.fetch("expires_at"))
  end

  def release_rollover_resources(receipt)
    task_id = submit_and_execute(
      "lease_release",
      client_id: OWNER.fetch(:agent_id),
      command_id: "audit2-rollover.release.owner",
      actor: { kind: "agent", id: OWNER.fetch(:agent_id) },
      change_set_id: ROLLOVER_CHANGE_SET_ID,
      work_item_id: OWNER.fetch(:work_item_id),
      attempt_id: OWNER.fetch(:attempt_id),
      lease_set_id: receipt.fetch("lease_set_id"),
      leases: lease_observations(receipt)
    )
    successful_rollover_task_data(task_id, client_id: OWNER.fetch(:agent_id))
  end

  def successful_rollover_task_data(task_id, client_id:)
    state = task_request("tasks/get", task_id, client_id:)
    result = state.dig("result", "result")
    assert_acceptance_equal("completed", state.dig("result", "status"), "Rollover setup Task")
    assert_acceptance_equal(false, result.fetch("isError"), "Rollover setup result")
    result.fetch("structuredContent").fetch("data")
  end

  def lease_observations(receipt)
    receipt.fetch("resources").map do |reference|
      {
        resource_id: reference.fetch("resource_id"),
        lease_id: reference.fetch("lease_id"),
        fencing_token: reference.fetch("fencing_token")
      }
    end
  end

  def rollover_resource_events(kind:, path:, maximum_count: 400)
    resource_id = (@acceptance_resource_ids || {}).fetch(
      [ acceptance_repository_id, kind, path ]
    )
    event_store.read(
      streams.resource_lease(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::RESOURCE_LEASE_LIFECYCLE_EVENT_TYPES,
        maximum_count:,
        direction: :asc
      )
    )
  end

  def rollover_markers(kind:, path:)
    Coordinator::Write::RepositoryMarkerBuilder.new.resource_boundary_markers(
      repository_id: acceptance_repository_id,
      resource_kind: kind,
      resource_path: path
    )
  end

  def rollover_boundary_marker(directory:, child_path:)
    event_markers = Coordinator::Write::RepositoryMarkerBuilder.new.resource_event_markers(
      repository_id: acceptance_repository_id,
      resource_kind: "file",
      resource_path: child_path
    )
    (event_markers & rollover_markers(kind: "directory", path: directory)).sole
  end

  def rollover_boundary_events(marker, maximum_count: 512)
    Coordinator::Write::EventQueries.resource_lease_boundary_pages(
      marker,
      from_position: 0,
      to_position: Coordinator::Write::EventQueries::RESOURCE_BOUNDARY_MAXIMUM_GLOBAL_POSITION,
      maximum_count:
    ).flat_map { event_store.read_global_marked_page(_1) }
      .sort_by(&:global_position)
  end

  def rollover_snapshots(marker)
    loader = Coordinator::Write::ResourceBoundaryLoader.new(event_store:)
    event_store.read_marked(
      loader.snapshot_stream(acceptance_repository_id),
      Coordinator::Write::MarkedEventReadCriteria.new(
        event_type: "ResourceBoundaryEpochRolled",
        marker:,
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def rollover_command_id(source, marker)
    markers = Coordinator::Write::RepositoryMarkerBuilder.new.resource_event_markers(
      repository_id: source.data.fetch("repository_id"),
      resource_kind: source.data.fetch("resource_kind"),
      resource_path: source.data.fetch("resource_path")
    ).sort_by(&:b)
    boundary_index = markers.index(marker) || raise("Source event does not carry the boundary marker")
    @rollover_race_process_step = process_step_event(
      source_event: source,
      process_name: "resource-boundary-maintenance",
      step_name: "roll-resource-boundary-epoch",
      subject_kind: "boundary-index",
      subject_id: boundary_index.to_s
    )
    assert_acceptance(@rollover_race_process_step, "Rollover has no persisted process step")
    @rollover_race_process_step.data.fetch("target_command_id")
  end

  def submit_rollover_contender(kind:, path:, await_terminal: true)
    response = call_tool(
      "write_set_reserve",
      {
        command_id: "audit2-rollover.reserve.contender",
        actor: { kind: "agent", id: CONTENDER.fetch(:agent_id) },
        change_set_id: ROLLOVER_CHANGE_SET_ID,
        work_item_id: CONTENDER.fetch(:work_item_id),
        attempt_id: CONTENDER.fetch(:attempt_id),
        repository_id: acceptance_repository_id,
        base_commit_oid: "a" * 40,
        resources: [
          resource_target(
            kind:,
            path:,
            client_id: CONTENDER.fetch(:agent_id),
            actor_id: CONTENDER.fetch(:agent_id)
          )
        ],
        lease_duration_seconds: 600
      },
      client_id: CONTENDER.fetch(:agent_id)
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "Rollover contender did not receive an MCP Task")
    state = await_task_terminal(task_id, client_id: CONTENDER.fetch(:agent_id)) if await_terminal
    { task_id:, state: }
  end

  def await_rollover_epoch(marker, count)
    eventually("resource boundary epoch #{count}", timeout_seconds: 120) do
      snapshots = rollover_snapshots(marker)
      [ snapshots.length >= count, snapshots.map { _1.data.fetch("epoch") } ]
    end
  end
end

World(ResourceBoundaryRolloverAcceptance)

After do
  @resource_boundary_rollover_gate&.close
end

Given("a directory boundary has exceeded the former lifecycle-history limit") do
  prepare_rollover_attempts
  @rollover_directory = "hot"
  @rollover_children = 32.times.map { "#{@rollover_directory}/child-#{_1}.rb" }
  @rollover_marker = rollover_boundary_marker(
    directory: @rollover_directory,
    child_path: @rollover_children.first
  )
  @rollover_receipt = reserve_rollover_resources(
    @rollover_children.map { { kind: "file", path: _1 } }
  )
  @rollover_receipt = renew_rollover_resources(@rollover_receipt, count: 3)
  await_rollover_epoch(@rollover_marker, 1)
  @rollover_receipt = renew_rollover_resources(@rollover_receipt, count: 4)
  await_rollover_epoch(@rollover_marker, 2)
  @rollover_receipt = renew_rollover_resources(@rollover_receipt, count: 1)
  assert_acceptance(
    rollover_boundary_events(@rollover_marker).length > 256,
    "The hot directory boundary did not exceed the former lifecycle limit"
  )
end

Given("every prior child lease on that boundary is released or expired") do
  release_rollover_resources(@rollover_receipt)
end

When("an agent reserves the directory through public MCP") do
  @rollover_contender = submit_rollover_contender(kind: "directory", path: @rollover_directory)
end

Then("the reservation Task completes successfully") do
  result = @rollover_contender.dig(:state, "result", "result")
  assert_acceptance_equal(
    "completed",
    @rollover_contender.dig(:state, "result", "status"),
    "Reservation Task"
  )
  assert_acceptance_equal(false, result.fetch("isError"), "Reservation result")
  assert_acceptance_equal("ok", result.dig("structuredContent", "status"), "Reservation outcome")
end

Then("its authoritative decision uses a bounded snapshot plus delta") do
  snapshots = rollover_snapshots(@rollover_marker)
  boundary = Coordinator::Write::ResourceBoundaryLoader.new(event_store:).call(
    [ @rollover_marker ],
    repository_id: acceptance_repository_id
  ).boundaries.sole

  assert_acceptance(snapshots.length >= 2, "The authoritative boundary has no rolled epochs")
  assert_acceptance(boundary.previous_through_global_position, "The decision did not load a snapshot")
  assert_acceptance(boundary.delta_count.between?(1, 256), "The decision delta was not bounded")
  assert_acceptance(
    boundary.states.any? do
      _1.attempt_id == ResourceBoundaryRolloverAcceptance::CONTENDER.fetch(:attempt_id) &&
        _1.active_at?(Time.now.utc.iso8601(6))
    end,
    "The bounded reconstruction omitted the successor lease"
  )
end

Given("two independent agents can reach the same resource-boundary decision concurrently") do
  prepare_rollover_attempts
  @rollover_directory = "hot-race"
  @rollover_children = 32.times.map { "#{@rollover_directory}/child-#{_1}.rb" }
  @rollover_race_marker = rollover_boundary_marker(
    directory: @rollover_directory,
    child_path: @rollover_children.first
  )
  receipt = reserve_rollover_resources(
    @rollover_children.first(31).map { { kind: "file", path: _1 } }
  )
  receipt = renew_rollover_resources(receipt, count: 1)
  receipt = expand_rollover_resources(
    receipt,
    resources: [ { kind: "file", path: @rollover_children.last } ]
  )
  @rollover_receipt = renew_rollover_resources(receipt, count: 2)
  assert_acceptance_equal(127, rollover_boundary_events(@rollover_race_marker).length, "Pre-race facts")
  @rollover_reservation_command_id = "audit2-rollover.reserve.contender"
  @resource_boundary_rollover_gate = ResourceBoundaryRolloverGate.new(
    reservation_command_id: @rollover_reservation_command_id
  )
end

When("the rollover command and conflicting reservation reach the deterministic database barrier") do
  release_rollover_resources(@rollover_receipt)
  lifecycle = rollover_boundary_events(@rollover_race_marker)
  @rollover_race_source = lifecycle.fetch(127)
  @rollover_race_command_id = rollover_command_id(@rollover_race_source, @rollover_race_marker)
  @rollover_race_contender = submit_rollover_contender(
    kind: "directory",
    path: @rollover_directory,
    await_terminal: false
  )
  @rollover_contention_evidence = @resource_boundary_rollover_gate.wait
  assert_acceptance_equal(
    @rollover_race_command_id,
    @rollover_contention_evidence.dig(:rollover, :command_id),
    "Rollover barrier command"
  )
end

When("the barrier releases both operations") do
  @resource_boundary_rollover_gate.release
  @rollover_race_contender[:state] = await_task_terminal(
    @rollover_race_contender.fetch(:task_id),
    client_id: ResourceBoundaryRolloverAcceptance::CONTENDER.fetch(:agent_id)
  )
  eventually("the raced boundary snapshot") do
    snapshots = rollover_snapshots(@rollover_race_marker)
    [ snapshots.any?, snapshots.map(&:id) ]
  end
end

Then("both operations terminate without a partial write") do
  result = @rollover_race_contender.dig(:state, "result", "result")
  assert_acceptance_equal(
    "completed",
    @rollover_race_contender.dig(:state, "result", "status"),
    "Raced Task"
  )
  assert_acceptance_equal(false, result.fetch("isError"), "Raced reservation")
  assert_acceptance_equal(1, rollover_snapshots(@rollover_race_marker).length, "Rollover facts")
  assert_acceptance_equal(
    1,
    rollover_resource_events(kind: "directory", path: @rollover_directory).length,
    "Directory lease facts"
  )
end

Then("the resulting boundary has at most one active overlapping lease") do
  boundary = Coordinator::Write::ResourceBoundaryLoader.new(event_store:).call(
    [ @rollover_race_marker ],
    repository_id: acceptance_repository_id
  )
  active = boundary.states.select { _1.active_at?(Time.now.utc.iso8601(6)) }

  assert_acceptance_equal(1, active.length, "The raced boundary active leases")
  assert_acceptance_equal(
    ResourceBoundaryRolloverAcceptance::CONTENDER.fetch(:attempt_id),
    active.sole.attempt_id,
    "Active lease owner"
  )
end

Then("every retry retains its logical event identities") do
  snapshot_ids = rollover_snapshots(@rollover_race_marker).map(&:id)
  lease_ids = rollover_resource_events(kind: "directory", path: @rollover_directory).map(&:id)
  replay = submit_rollover_contender(kind: "directory", path: @rollover_directory)
  snapshot = rollover_snapshots(@rollover_race_marker).sole

  assert_acceptance_equal(false, replay.dig(:state, "result", "result", "isError"), "Reservation replay")
  assert_acceptance_equal(snapshot_ids, rollover_snapshots(@rollover_race_marker).map(&:id), "Rollover identities")
  assert_acceptance_equal(
    lease_ids,
    rollover_resource_events(kind: "directory", path: @rollover_directory).map(&:id),
    "Reservation identities"
  )
  assert_acceptance_equal(@rollover_race_command_id, snapshot.metadata.fetch("command_id"), "Rollover command")
  assert_acceptance_equal(@rollover_race_process_step.id, snapshot.causation_id, "Rollover causation")
  assert_acceptance_equal(@rollover_race_source.correlation_id, snapshot.correlation_id, "Rollover correlation")
end
