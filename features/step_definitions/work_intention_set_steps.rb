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
  "both agents concurrently declare initial work intentions overlapping on {string}"
) do |shared_path|
  @shared_lease_path = shared_path
  @reservation_tasks = @lease_participants.map.with_index do |participant, index|
    mode = index.zero? ? "shared" : "exclusive"
    purpose = index.zero? ? "Append compatible schema changes" : "Replace the schema structure"
    context = "#{participant.fetch(:attempt_id)} plans #{mode} work"
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
          mode:,
          purpose:,
          context:,
          actor_id: participant.fetch(:agent_id)
        ),
        resource_target(
          kind: "file",
          path: shared_path,
          mode:,
          purpose:,
          context:,
          actor_id: participant.fetch(:agent_id)
        )
      ],
      ttl_seconds: 300
    }
    task_id = call_tool("work_intention_set_declare", arguments).dig("result", "taskId")
    participant.merge(task_id:, arguments:, mode:, purpose:, context:)
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
  blocker = @losing_reservation.dig(:outcome, "data", "details", "blockers").sole
  assert_acceptance_equal(
    @winning_reservation.fetch(:attempt_id),
    blocker.fetch("owner_attempt_id"),
    "Persisted busy owner"
  )
  assert_acceptance_equal(@winning_reservation.fetch(:mode), blocker.fetch("mode"), "Blocking mode")
  assert_acceptance_equal(@winning_reservation.fetch(:purpose), blocker.fetch("purpose"), "Blocking purpose")
  assert_acceptance_equal(@winning_reservation.fetch(:context), blocker.fetch("context"), "Blocking context")
  assert_acceptance(blocker.fetch("expires_at"), "Blocking expiry must be supplied")
end

Then("the winner owns its complete write set") do
  expected_paths = [ @winning_reservation.fetch(:unique_path), @shared_lease_path ].sort
  assert_acceptance_equal(
    expected_paths,
    @winning_reservation.dig(:outcome, "data", "intentions").map { _1.fetch("resource_path") }.sort,
    "Winning intention-set resources"
  )
  assert_acceptance_equal(
    [ "WorkIntentionSetCreated", "WorkIntentionAddedToSet", "WorkIntentionAddedToSet" ],
    work_intention_set_events(@winning_reservation.fetch(:attempt_id)).map(&:type),
    "Winning intention-set facts"
  )
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionDeclared" ],
    work_intention_events_for_attempt(@winning_reservation.fetch(:attempt_id)).map(&:type),
    "Winning intention facts"
  )
end

Then("the loser owns no partial write set") do
  assert_acceptance_equal(
    [],
    work_intention_set_events(@losing_reservation.fetch(:attempt_id)),
    "Losing Attempt intention set"
  )
  assert_acceptance_equal(
    [],
    work_intention_events_for_command(@losing_reservation.dig(:arguments, :command_id)),
    "Losing command intention facts"
  )
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@losing_reservation.dig(:arguments, :command_id)).map(&:type),
    "Losing command lifecycle"
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
  write_set = attempt.fetch("work_intention_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Available context status")
  assert_acceptance(!payload.key?("projection_status"), "Context must not expose a projection gate")
  assert_acceptance_equal(
    [ @shared_lease_path, @winning_reservation.fetch(:unique_path) ].sort,
    write_set.fetch("intentions").map { _1.fetch("resource_path") }.sort,
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
    "work_intention_set_declare",
    command_id: "cmd-cuc-expand-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @expansion_work_item_id,
    attempt_id:,
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path: initial_path, actor_id: agent_id) ],
    ttl_seconds: 300
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
    "work_intention_set_expand",
    {
      command_id: @expansion_command_id,
      actor: { kind: "agent", id: @expansion_agent_id },
      change_set_id: @expansion_change_set_id,
      work_item_id: @expansion_work_item_id,
      attempt_id: @expansion_attempt_id,
      intention_set_id: @expansion_reservation.fetch("intention_set_id"),
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
    @expansion_reservation.fetch("intention_set_id"),
    data.fetch("intention_set_id"),
    "Expansion lease-set identity"
  )
  assert_acceptance_equal(
    @expansion_reservation.fetch("expires_at"),
    data.fetch("expires_at"),
    "Expansion deadline"
  )
  assert_acceptance_equal(
    [ @expansion_additional_path ],
    data.fetch("added_intentions").map { _1.fetch("resource_path") },
    "Expansion additions"
  )
end

Then("the previous context remains available before expansion projection") do
  lagging = call_tool("coord_context", { attempt_id: @expansion_attempt_id })
  before_payload = @context_before_expansion.dig("result", "structuredContent")
  lagging_payload = lagging.dig("result", "structuredContent")
  write_set = lagging_payload.dig("data", "context", "attempts", 0, "work_intention_set")

  assert_acceptance_equal("ok", lagging_payload.fetch("status"), "Lagging context status")
  assert_acceptance_equal(
    before_payload.fetch("context_token"),
    lagging_payload.fetch("context_token"),
    "Lagging context token"
  )
  assert_acceptance_equal(
    [ @expansion_initial_path ],
    write_set.fetch("intentions").map { _1.fetch("resource_path") },
    "Lagging write-set evidence"
  )
end

When("the write-set expansion reaches the read side") do
  @expanded_context = await_read_model("Write-set expansion to become available") do
    response = call_tool("coord_context", { attempt_id: @expansion_attempt_id })
    resources = response.dig(
      "result", "structuredContent", "data", "context", "attempts", 0, "work_intention_set", "intentions"
    ) || []
    [ resources.any? { _1.fetch("resource_path") == @expansion_additional_path }, response ]
  end
end

Then("available context exposes both observed files without a freshness claim") do
  payload = @expanded_context.dig("result", "structuredContent")
  write_set = payload.dig("data", "context", "attempts", 0, "work_intention_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Expanded context status")
  assert_acceptance_equal(
    [ @expansion_initial_path, @expansion_additional_path ].sort,
    write_set.fetch("intentions").map { _1.fetch("resource_path") }.sort,
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
    "work_intention_set_declare",
    command_id: "cmd-cuc-renew-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @renewal_work_item_id,
    attempt_id:,
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: @renewal_paths.map { resource_target(kind: "file", path: _1, actor_id: agent_id) },
    ttl_seconds: 300
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
  @renewal_expected_previous_deadline = @renewal_reservation.fetch("expires_at")
  @renewal_task_id = call_tool(
    "work_intention_set_renew",
    {
      command_id: "cmd-cuc-renew-set",
      actor: { kind: "agent", id: @renewal_agent_id },
      change_set_id: @renewal_change_set_id,
      work_item_id: @renewal_work_item_id,
      attempt_id: @renewal_attempt_id,
      intention_set_id: @renewal_reservation.fetch("intention_set_id"),
      intentions: @renewal_reservation.fetch("intentions").map do |reference|
        {
          resource_id: reference.fetch("resource_id"),
          intention_id: reference.fetch("intention_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end,
      ttl_seconds: 600
    }
  ).dig("result", "taskId")
  execute_task(@renewal_task_id)
  @renewal_task_state = task_request("tasks/get", @renewal_task_id)
end

When("the agent renews the same intention set again") do
  @renewal_expected_previous_deadline = @renewal_result.fetch("expires_at")
  @renewal_task_id = call_tool(
    "work_intention_set_renew",
    {
      command_id: "cmd-cuc-renew-set-again",
      actor: { kind: "agent", id: @renewal_agent_id },
      change_set_id: @renewal_change_set_id,
      work_item_id: @renewal_work_item_id,
      attempt_id: @renewal_attempt_id,
      intention_set_id: @renewal_reservation.fetch("intention_set_id"),
      intentions: @renewal_result.fetch("intentions").map do |reference|
        reference.slice("resource_id", "intention_id", "fencing_token")
      end,
      ttl_seconds: 900
    }
  ).dig("result", "taskId")
  execute_task(@renewal_task_id)
  @renewal_task_state = task_request("tasks/get", @renewal_task_id)
end

Then("the renewal Task succeeds without changing lease identities or fencing tokens") do
  result = @renewal_task_state.dig("result", "result")
  data = result.fetch("structuredContent").fetch("data")
  before_refs = @renewal_reservation.fetch("intentions").map do |reference|
    reference.values_at("resource_id", "intention_id", "fencing_token")
  end
  after_refs = data.fetch("intentions").map do |reference|
    reference.values_at("resource_id", "intention_id", "fencing_token")
  end

  assert_acceptance_equal("completed", @renewal_task_state.dig("result", "status"), "Renewal Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Renewal tool error flag")
  assert_acceptance_equal(before_refs, after_refs, "Renewed lease references")
  assert_acceptance_equal(
    @renewal_expected_previous_deadline,
    data.fetch("previous_expires_at"),
    "Renewal previous deadline"
  )
  assert_acceptance(
    data.fetch("expires_at") > @renewal_expected_previous_deadline,
    "Renewal must move the deadline forward"
  )
  @renewal_result = data
end

Then("the previous context remains available before renewal projection") do
  lagging = call_tool("coord_context", { attempt_id: @renewal_attempt_id })
  before_payload = @context_before_renewal.dig("result", "structuredContent")
  lagging_payload = lagging.dig("result", "structuredContent")
  write_set = lagging_payload.dig("data", "context", "attempts", 0, "work_intention_set")

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
      "result", "structuredContent", "data", "context", "attempts", 0, "work_intention_set", "expires_at"
    )
    [ observed == @renewal_result.fetch("expires_at"), response ]
  end
end

Then("available context exposes the later observed deadline without a freshness claim") do
  payload = @renewed_context.dig("result", "structuredContent")
  write_set = payload.dig("data", "context", "attempts", 0, "work_intention_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Renewed context status")
  assert_acceptance_equal(@renewal_result.fetch("expires_at"), write_set.fetch("expires_at"), "Observed deadline")
  assert_acceptance_equal(
    @renewal_expected_previous_deadline,
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
    "work_intention_set_declare",
    command_id: "cmd-cuc-release-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id:,
    work_item_id: @release_work_item_id,
    attempt_id:,
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: @release_paths.map { resource_target(kind: "file", path: _1, actor_id: agent_id) },
    ttl_seconds: 300
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
    "work_intention_set_withdraw",
    {
      command_id: "cmd-cuc-release-set",
      actor: { kind: "agent", id: @release_agent_id },
      change_set_id: @release_change_set_id,
      work_item_id: @release_work_item_id,
      attempt_id: @release_attempt_id,
      intention_set_id: @release_reservation.fetch("intention_set_id"),
      intentions: @release_reservation.fetch("intentions").map do |reference|
        {
          resource_id: reference.fetch("resource_id"),
          intention_id: reference.fetch("intention_id"),
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
  before_refs = @release_reservation.fetch("intentions").map do |reference|
    reference.values_at("resource_id", "intention_id", "fencing_token")
  end
  after_refs = data.fetch("intentions").map do |reference|
    reference.values_at("resource_id", "intention_id", "fencing_token")
  end

  assert_acceptance_equal("completed", @release_task_state.dig("result", "status"), "Release Task status")
  assert_acceptance_equal(false, result.fetch("isError"), "Release tool error flag")
  assert_acceptance_equal(before_refs, after_refs, "Released lease references")
  assert_acceptance_equal(
    @release_reservation.fetch("expires_at"),
    data.fetch("previous_expires_at"),
    "Release previous deadline"
  )
  assert_acceptance(data.fetch("withdrawn_at"), "Release timestamp is missing")
  @release_reservation.fetch("intentions").each do |reference|
    assert_acceptance_equal(
      [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionWithdrawn" ],
      work_intention_events(reference.fetch("intention_id")).map(&:type),
      "Withdrawn work-intention lifecycle"
    )
  end
  @release_result = data
end

Then("the previous context remains available before release projection") do
  lagging = call_tool("coord_context", { attempt_id: @release_attempt_id })
  before_payload = @context_before_release.dig("result", "structuredContent")
  lagging_payload = lagging.dig("result", "structuredContent")
  write_set = lagging_payload.dig("data", "context", "attempts", 0, "work_intention_set")

  assert_acceptance_equal("ok", lagging_payload.fetch("status"), "Lagging release context status")
  assert_acceptance_equal(
    before_payload.fetch("context_token"),
    lagging_payload.fetch("context_token"),
    "Lagging release context token"
  )
  assert_acceptance_equal(nil, write_set.fetch("withdrawn_at"), "Lagging observed release")
  assert_acceptance_equal(
    @release_paths.sort,
    write_set.fetch("intentions").map { _1.fetch("resource_path") }.sort,
    "Lagging release resources"
  )
  assert_acceptance(!lagging_payload.key?("projection_status"), "Lagging context must remain available")
end

When("the write-set release reaches the read side") do
  @released_context = await_read_model("Write-set release to become available") do
    response = call_tool("coord_context", { attempt_id: @release_attempt_id })
    observed = response.dig(
      "result", "structuredContent", "data", "context", "attempts", 0, "work_intention_set", "withdrawn_at"
    )
    [ observed == @release_result.fetch("withdrawn_at"), response ]
  end
end

Then("available context exposes the observed release without a freshness claim") do
  payload = @released_context.dig("result", "structuredContent")
  write_set = payload.dig("data", "context", "attempts", 0, "work_intention_set")

  assert_acceptance_equal("ok", payload.fetch("status"), "Released context status")
  assert_acceptance_equal(@release_result.fetch("withdrawn_at"), write_set.fetch("withdrawn_at"), "Observed release")
  assert_acceptance_equal(
    @release_reservation.fetch("expires_at"),
    write_set.fetch("expires_at"),
    "Retained observed deadline"
  )
  assert_acceptance_equal(
    @release_paths.sort,
    write_set.fetch("intentions").map { _1.fetch("resource_path") }.sort,
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
    "work_intention_set_declare",
    {
      command_id: @expiry_predecessor_command_id,
      actor: { kind: "agent", id: agent_id },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_predecessor.fetch(:work_item_id),
      attempt_id: @expiry_predecessor.fetch(:attempt_id),
      repository_id: acceptance_repository_id,
      base_commit_oid: "a" * 40,
      resources: [
        resource_target(
          kind: "file",
          path:,
          mode: "exclusive",
          purpose: "Replace #{path}",
          context: "The predecessor requires exclusive access for this operation.",
          actor_id: agent_id
        )
      ],
      ttl_seconds: duration
    }
  ).dig("result", "taskId")
  execute_task(@expiry_predecessor_task_id)
  @expiry_predecessor_state = task_request("tasks/get", @expiry_predecessor_task_id)
  @expiry_predecessor_result = @expiry_predecessor_state.dig(
    "result", "result", "structuredContent", "data"
  )
  @expiry_source = work_intention_events(
    @expiry_predecessor_result.fetch("intentions").sole.fetch("intention_id")
  ).sole
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
      ttl_seconds: 300
    }
    task_id = call_tool("work_intention_set_declare", arguments).dig("result", "taskId")
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
    assert_acceptance_equal(
      [ reservation.fetch(:unique_path) ],
      reservation.dig(:outcome, "data", "intentions").map { _1.fetch("resource_path") },
      "Disjoint complete intention set"
    )
    assert_acceptance_equal(
      [ "WorkIntentionSetCreated", "WorkIntentionAddedToSet" ],
      work_intention_set_events(reservation.fetch(:attempt_id)).map(&:type),
      "Disjoint intention-set facts"
    )
    assert_acceptance_equal(
      [ "ResourceWorkIntentionDeclared" ],
      work_intention_events_for_attempt(reservation.fetch(:attempt_id)).map(&:type),
      "Disjoint intention facts"
    )
  end
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
    ttl_seconds: 300
  }
  @cancelled_reservation_task_id = call_tool("work_intention_set_declare", arguments).dig("result", "taskId")
  task_request("tasks/cancel", @cancelled_reservation_task_id)
  execute_task(@cancelled_reservation_task_id)
  @cancelled_reservation_state = task_request("tasks/get", @cancelled_reservation_task_id)
end

Then("the cancelled reservation writes no work-intention fact") do
  assert_acceptance_equal("cancelled", @cancelled_reservation_state.dig("result", "status"), "Task status")
  assert_acceptance_equal(
    [],
    work_intention_set_events(@cancelled_reservation_owner.fetch(:attempt_id)),
    "Cancelled Attempt intention set"
  )
  assert_acceptance_equal(
    [],
    work_intention_events_for_command(@cancelled_reservation_command_id),
    "Cancelled command intention facts"
  )
  assert_acceptance_equal(
    [ "CommandRegistered" ],
    command_events(@cancelled_reservation_command_id).map(&:type),
    "Cancelled command facts"
  )
end

When("agent {string} deliberately reserves {string}") do |agent_id, path|
  participant = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  task_id = submit_and_execute(
    "work_intention_set_declare",
    command_id: "cmd-cuc-lse-deliberate-reserve",
    actor: { kind: "agent", id: agent_id },
    change_set_id: @lease_change_set_id,
    work_item_id: participant.fetch(:work_item_id),
    attempt_id: participant.fetch(:attempt_id),
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path:, actor_id: agent_id) ],
    ttl_seconds: 300
  )
  @successor_result = task_request("tasks/get", task_id).dig(
    "result", "result", "structuredContent", "data"
  )
end

Then("the successor obtains fencing token {int}") do |expected_token|
  assert_acceptance_equal(
    expected_token,
    @successor_result.fetch("intentions").sole.fetch("fencing_token"),
    "Successor fencing token"
  )
end

When("the exact release command is submitted again") do
  arguments = {
    command_id: "cmd-cuc-release-set",
    actor: { kind: "agent", id: @release_agent_id },
    change_set_id: @release_change_set_id,
    work_item_id: @release_work_item_id,
    attempt_id: @release_attempt_id,
    intention_set_id: @release_reservation.fetch("intention_set_id"),
    intentions: @release_reservation.fetch("intentions").map do |reference|
      reference.slice("resource_id", "intention_id", "fencing_token").transform_keys(&:to_sym)
    end
  }
  @release_retry_task_id = call_tool("work_intention_set_withdraw", arguments).dig("result", "taskId")
  execute_task(@release_retry_task_id)
  @release_retry_task_state = task_request("tasks/get", @release_retry_task_id)
end

Then("both release responses expose the original Task and one logical result") do
  assert_acceptance_equal(@release_task_id, @release_retry_task_id, "Release replay Task identity")
  assert_acceptance_equal(
    @release_task_state.dig("result", "result"),
    @release_retry_task_state.dig("result", "result"),
    "Release replay result"
  )
  @release_reservation.fetch("intentions").each do |reference|
    assert_acceptance_equal(
      1,
      work_intention_events(reference.fetch("intention_id")).count { _1.type == "ResourceWorkIntentionWithdrawn" },
      "Replayed withdrawal fact"
    )
  end
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events("cmd-cuc-release-set").map(&:type),
    "Release command lifecycle"
  )
end

When("the predecessor releases its exact lease set") do
  @predecessor_release_task_id = call_tool(
    "work_intention_set_withdraw",
    {
      command_id: "cmd-cuc-release-predecessor",
      actor: { kind: "agent", id: @expiry_predecessor.fetch(:agent_id) },
      change_set_id: @lease_change_set_id,
      work_item_id: @expiry_predecessor.fetch(:work_item_id),
      attempt_id: @expiry_predecessor.fetch(:attempt_id),
      intention_set_id: @expiry_predecessor_result.fetch("intention_set_id"),
      intentions: @expiry_predecessor_result.fetch("intentions").map do |reference|
        reference.slice("resource_id", "intention_id", "fencing_token").transform_keys(&:to_sym)
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
    [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionWithdrawn" ],
    work_intention_events(
      @expiry_predecessor_result.fetch("intentions").sole.fetch("intention_id")
    ).map(&:type),
    "Withdrawn intention lifecycle"
  )
end

When("agent {string} deliberately reserves after the release") do |agent_id|
  participant = @lease_participants.find { _1.fetch(:agent_id) == agent_id }
  task_id = submit_and_execute(
    "work_intention_set_declare",
    command_id: "cmd-cuc-release-successor",
    actor: { kind: "agent", id: agent_id },
    change_set_id: @lease_change_set_id,
    work_item_id: participant.fetch(:work_item_id),
    attempt_id: participant.fetch(:attempt_id),
    repository_id: acceptance_repository_id,
    base_commit_oid: "a" * 40,
    resources: [ resource_target(kind: "file", path: @expiry_path, actor_id: agent_id) ],
    ttl_seconds: 300
  )
  @successor_result = task_request("tasks/get", task_id).dig(
    "result", "result", "structuredContent", "data"
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
    %w[attempt_id reason],
    abandonment_events.sole.data.keys.sort,
    "AttemptAbandoned fact boundary"
  )
  @release_reservation.fetch("intentions").each do |reference|
    assert_acceptance_equal(
      [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionWithdrawn" ],
      work_intention_events(reference.fetch("intention_id")).map(&:type),
      "Abandoned work-intention lifecycle for #{reference.fetch("resource_path")}"
    )
  end
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(@abandonment_arguments.fetch(:command_id)).map(&:type),
    "Command lifecycle"
  )
end

When("the exact abandonment command is submitted again") do
  @abandonment_retry_task_id = call_tool(
    "attempt_abandon",
    @abandonment_arguments
  ).dig("result", "taskId")
  execute_task(@abandonment_retry_task_id)
  @abandonment_retry_task_state = task_request("tasks/get", @abandonment_retry_task_id)
end

Then("both abandonment responses expose the original Task and one logical result") do
  assert_acceptance_equal(
    @abandonment_task_id,
    @abandonment_retry_task_id,
    "Abandonment replay Task identity"
  )
  assert_acceptance_equal(
    @abandonment_task_state.dig("result", "result"),
    @abandonment_retry_task_state.dig("result", "result"),
    "Abandonment replay result"
  )
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(@abandonment_arguments.fetch(:command_id)).map(&:type),
    "Abandonment command lifecycle"
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
  fresh_events = event_store.read(
    streams.attempt(@fresh_attempt_id),
    Coordinator::Write::EventQueries::ATTEMPT_FOR_WORK_INTENTIONS
  )
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
    [
      "AttemptAuthorized",
      "AttemptAssignedToWorkItem",
      "AttemptAssignedToAgent",
      "AttemptBaseSnapshotRecorded",
      "AttemptStarted"
    ],
    fresh_events.map(&:type),
    "Fresh Attempt lifecycle"
  )
  assert_acceptance_equal(
    @fresh_base_commit_oid,
    fresh_events.find { _1.type == "AttemptBaseSnapshotRecorded" }.data.fetch("commit_oid"),
    "Fresh base snapshot"
  )
  assert_acceptance_equal(@release_attempt_id, abandonment.data.fetch("attempt_id"), "Terminal old Attempt")
  assert_acceptance_equal(@fresh_attempt_id, current_work_item.data.fetch("attempt_id"), "Current WorkItem Attempt")
end

Given(
  "agent {string} has submitted {string} Candidate {string} for active Attempt {string}"
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
      event_types: [ "AttemptAbandoned" ],
      maximum_count: 1,
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
  assert_acceptance_equal([], attempt_terminal_events.map(&:type), "Attempt facts")
  assert_acceptance(
    candidate_events(@candidate_abandonment_candidate_id).any? { _1.type == "CandidateSubmitted" },
    "Final Candidate submission must remain recorded"
  )
  assert_acceptance_equal([], requeue_events, "WorkItem requeue facts")
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared" ],
    candidate_work_intention_events(coordination).map(&:type),
    "Candidate work-intention lifecycle"
  )
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@candidate_abandonment_command_id).map(&:type),
    "Denied command lifecycle"
  )
end

Then("the checkpoint remains recorded while the Attempt is abandoned and requeued") do
  coordination = @candidate_abandonment_coordination
  ids = coordination.fetch(:ids)
  result = @candidate_abandonment_state.dig("result", "result")
  payload = result.fetch("structuredContent")
  attempt_terminal_events = event_store.read(
    streams.attempt(ids.fetch(:attempt_id)),
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "AttemptAbandoned" ],
      maximum_count: 1,
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
    [ "AttemptAbandoned" ],
    attempt_terminal_events.map(&:type),
    "Attempt facts"
  )
  assert_acceptance(
    candidate_events(@candidate_abandonment_candidate_id).any? { _1.type == "CandidateSubmitted" },
    "Intermediate Candidate submission must remain recorded"
  )
  assert_acceptance_equal([ "WorkItemRequeued" ], requeue_events.map(&:type), "WorkItem requeue facts")
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionWithdrawn" ],
    candidate_work_intention_events(coordination).map(&:type),
    "Intermediate Candidate work-intention lifecycle"
  )
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(@candidate_abandonment_command_id).map(&:type),
    "Command lifecycle"
  )
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
    mode: "shared",
    purpose: nil,
    context: nil,
    command_suffix: nil,
    command_id: nil,
    await_terminal: true
  )
    participant = @hierarchical_participants.find { _1.fetch(:agent_id) == agent_id }
    assert_acceptance(participant, "Unknown hierarchy participant #{agent_id}")
    command_id ||= "#{@hierarchical_change_set_id.downcase}.reserve.#{command_suffix}"
    response = call_tool(
      "work_intention_set_declare",
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
            mode:,
            purpose: purpose || "Coordinate #{path}",
            context:,
            client_id: agent_id,
            actor_id: agent_id
          )
        ],
        ttl_seconds: 300
      },
      client_id: agent_id
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "work_intention_set_declare did not return a Task: #{response.inspect}")

    {
      agent_id:,
      kind:,
      path:,
      mode:,
      purpose: purpose || "Coordinate #{path}",
      context:,
      command_id:,
      task_id:,
      client_id: agent_id,
      state: await_terminal ? await_task_terminal(task_id, client_id: agent_id) : nil
    }
  end

  def hierarchical_intention_events(reservation)
    data = hierarchical_outcome(reservation).fetch("data")
    data.fetch("intentions").flat_map do |reference|
      work_intention_events(reference.fetch("intention_id"))
    end
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
  "agent {string} declares a(n) {word} intention for {word} {string} through a public Task"
) do |agent_id, mode, kind, path|
  @hierarchical_reservations << submit_live_hierarchical_reservation(
    agent_id:,
    kind:,
    path:,
    mode:,
    purpose: "#{mode.capitalize} work on #{path}",
    context: "Declared by #{agent_id} for #{@hierarchical_change_set_id}",
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

Then("only the current file resource has a durable intention declaration") do
  reservation = @hierarchical_reservations.sole
  assert_acceptance_equal("file", reservation.fetch(:kind), "Current Resource kind")
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared" ],
    hierarchical_intention_events(reservation).map(&:type),
    "Current Resource lifecycle"
  )
end

Then("the first hierarchical intention succeeds and the second completes busy with its blocker context") do
  first, second = @hierarchical_reservations
  assert_acceptance_equal("completed", first.dig(:state, "result", "status"), "First Task status")
  assert_acceptance_equal("ok", hierarchical_outcome(first).fetch("status"), "First reservation")
  assert_acceptance_equal("completed", second.dig(:state, "result", "status"), "Second Task status")
  assert_acceptance_equal("busy", hierarchical_outcome(second).fetch("status"), "Second reservation")
  blocker = hierarchical_outcome(second).dig("data", "details", "blockers").sole
  assert_acceptance_equal(first.fetch(:agent_id), blocker.fetch("owner_agent_id"), "Blocking owner")
  assert_acceptance_equal(first.fetch(:mode), blocker.fetch("mode"), "Blocking mode")
  assert_acceptance_equal(first.fetch(:purpose), blocker.fetch("purpose"), "Blocking purpose")
  assert_acceptance_equal(first.fetch(:context), blocker.fetch("context"), "Blocking context")
  assert_acceptance_equal(
    {
      "repository_id" => acceptance_repository_id,
      "change_set_id" => @hierarchical_change_set_id,
      "work_item_id" => @hierarchical_participants.first.fetch(:work_item_id)
    },
    blocker.fetch("scope"),
    "Blocking scope"
  )
end

Then("only the {word} resource has a durable intention declaration") do |winning_kind|
  winning = @hierarchical_reservations.first
  losing = @hierarchical_reservations.last
  assert_acceptance_equal(winning_kind, winning.fetch(:kind), "Winning resource kind")
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared" ],
    hierarchical_intention_events(winning).map(&:type),
    "Winning lifecycle"
  )
  assert_acceptance_equal(
    [],
    work_intention_events_for_command(losing.fetch(:command_id)),
    "Losing lifecycle"
  )
end

When("both agents submit public reservation Tasks for disjoint resources and reach the reservation decision boundary") do
  agent_ids = [ "agent-a", "agent-b" ]
  prepare_mcp_clients(*agent_ids)
  requests = [
    { agent_id: "agent-a", kind: "directory", path: "app/models" },
    {
      agent_id: "agent-b",
      kind: "file",
      path: "spec/services/user_spec.rb"
    }
  ]
  requests.each do |arguments|
    resource_target(
      kind: arguments.fetch(:kind),
      path: arguments.fetch(:path),
      client_id: arguments.fetch(:agent_id),
      actor_id: arguments.fetch(:agent_id)
    )
  end
  @hierarchical_reservations = submit_tasks_in_distinct_execution_lanes(client_ids: agent_ids) do |agent_id, round|
    arguments = requests.find { _1.fetch(:agent_id) == agent_id }
    submit_live_hierarchical_reservation(
      **arguments,
      command_id: "#{@hierarchical_change_set_id.downcase}.reserve.disjoint.#{agent_id}.#{round}",
      await_terminal: false
    )
  end
  install_contention_barrier(
    operation: "coordination_task_execute",
    command_ids: @hierarchical_reservations.map { _1.fetch(:internal_command_id) }
  )
  start_process_subscriptions
  await_contention_evidence
end

Then("both reservation operations have deterministic contention evidence") do
  assert_acceptance_equal(2, @contention_evidence.length, "Reservation boundary arrivals")
  assert_acceptance_equal(
    @hierarchical_reservations.map { _1.fetch(:internal_command_id) }.sort,
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
      [ "ResourceWorkIntentionDeclared" ],
      hierarchical_intention_events(reservation).map(&:type),
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

Then("no work intention is stored for either path spelling") do
  assert_acceptance_equal([], command_events(@literal_path_command_id), "Command facts")
  intentions = PgEventstore.client.read(
    PgEventstore::Stream.all_stream,
    options: {
      direction: :asc,
      max_count: 1,
      filter: { event_types: [ { type: "ResourceWorkIntentionDeclared" } ] }
    }
  )
  assert_acceptance_equal([], intentions, "Work-intention facts")
end
