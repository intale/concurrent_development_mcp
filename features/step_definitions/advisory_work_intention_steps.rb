# frozen_string_literal: true

Given("two MCP agents have active Attempts in the same project") do
  prepare_advisory_work_intention_agents
end

Given("compatible shared work has accumulated more than the intention boundary budget") do
  prepare_exhausted_advisory_boundary
end

When("agent B requests a shared intention set {word} over that history") do |operation|
  submit_exhausted_advisory_request(operation)
end

Then("the history-budget Task completes with a typed limit result rather than an execution failure") do
  result = @advisory_capacity_task.fetch("result")
  assert_acceptance_equal("completed", result.fetch("status"), "History-budget Task status")
  assert_acceptance_equal(true, result.dig("result", "isError"), "History-budget tool denial")
  outcome = result.dig("result", "structuredContent")
  assert_acceptance_equal("limit_reached", outcome.fetch("status"), "History-budget semantic status")
  assert_acceptance_equal("resource_boundary_maintenance_required", outcome.dig("data", "code"), "History-budget code")
  assert_acceptance_equal(
    Coordinator::Write::EventQueries::WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT,
    outcome.dig("data", "details", "maximum_delta_event_count"),
    "History-budget bound"
  )
end

Then("the denied request records no partial intentions or membership changes") do
  events = work_intention_events_for_attempt(advisory_agent("B").fetch(:attempt_id))
  declarations = events.select { _1.type == "ResourceWorkIntentionDeclared" }
  if @advisory_capacity_operation == "expansion"
    expected = advisory_intention_reference(@advisory_capacity_existing)
    assert_acceptance_equal([ expected.fetch("intention_id") ], declarations.map { _1.data.fetch("intention_id") }, "Existing intentions")
    set = Coordinator::Write::WorkIntentionSetLoader.new(event_store: event_store).call(
      @advisory_capacity_existing.dig(:outcome, "data", "intention_set_id")
    )
    assert_acceptance_equal([ expected.fetch("resource_id") ], set.members.map(&:resource_id), "Unchanged membership")
  else
    assert_acceptance_equal([], declarations, "No partial declaration")
    set = Coordinator::Write::WorkIntentionSetLoader.new(event_store: event_store).find_by_attempt(
      advisory_agent("B").fetch(:attempt_id)
    )
    assert_acceptance_equal(nil, set, "No partial set")
  end
end

When("both agents concurrently declare shared intentions for {string}") do |path|
  resource_a = advisory_resource("file", path, agent: advisory_agent("A"))
  resource_b = resource_a.merge(
    resource_id: resolve_resource_id(
      kind: "file",
      path:,
      client_id: advisory_agent("B").fetch(:client_id),
      actor_id: advisory_agent("B").fetch(:agent_id)
    )
  )
  submissions = [
    [ advisory_agent("A"), resource_a, "cuc-advisory-shared-a" ],
    [ advisory_agent("B"), resource_b, "cuc-advisory-shared-b" ]
  ].map do |agent, resource, command_id|
    Thread.new do
      submit_advisory_declaration(agent:, resource:, mode: "shared", command_id:)
    end
  end.map(&:value)
  start_process_subscriptions
  @advisory_shared_declarations = submissions.map { await_advisory_declaration(_1) }
end

Then("both intention Tasks complete successfully") do
  @advisory_shared_declarations.each do |declaration|
    assert_acceptance_equal("completed", declaration.dig(:state, "result", "status"), "Intention Task status")
    assert_acceptance_equal(false, declaration.dig(:state, "result", "result", "isError"), "Intention Task result")
    assert_acceptance_equal("ok", declaration.dig(:outcome, "status"), "Intention semantic status")
  end
end

Then("each active intention retains its agent, Attempt, purpose, context, and expiry") do
  @advisory_shared_declarations.each do |declaration|
    reference = advisory_intention_reference(declaration)
    event = work_intention_events(reference.fetch("intention_id")).find do |candidate|
      candidate.type == "ResourceWorkIntentionDeclared"
    end
    assert_acceptance(event, "Declared work-intention event")
    assert_acceptance_equal(declaration.dig(:agent, :agent_id), event.data.fetch("agent_id"), "Agent attribution")
    assert_acceptance_equal(declaration.dig(:agent, :attempt_id), event.data.fetch("attempt_id"), "Attempt attribution")
    assert_acceptance_equal(declaration.dig(:arguments, :resources).sole.fetch(:purpose), event.data.fetch("purpose"), "Purpose")
    assert_acceptance_equal(declaration.dig(:arguments, :resources).sole.fetch(:context), event.data.fetch("context"), "Context")
    assert_acceptance_equal(declaration.dig(:outcome, "data", "expires_at"), event.data.fetch("expires_at"), "Expiry")
  end
end

Then("neither agent is promised that its eventual Git changes will merge cleanly") do
  instructions = mcp_request(method: "server/discover", params: {}, client_id: "agent-a").dig("result", "instructions")
  assert_acceptance(
    instructions.include?("never queues, waits, preempts, or promises") &&
      instructions.include?("shared changes will merge cleanly"),
    "MCP guidance must state the advisory merge limitation"
  )
end

Given("agent A has an active {word} intention for {word} {word}") do |mode, kind, path|
  agent = advisory_agent("A")
  resource = advisory_resource(kind, path, agent:)
  @advisory_existing = declare_advisory_intention(
    agent:,
    resource:,
    mode:,
    command_id: "cuc-advisory-existing-#{mode}-#{kind}"
  )
  assert_acceptance_equal("ok", @advisory_existing.dig(:outcome, "status"), "Existing intention")
end

When("agent B declares a {word} intention for {word} {word}") do |mode, kind, path|
  agent = advisory_agent("B")
  resource = advisory_resource(kind, path, agent:)
  @advisory_requested = declare_advisory_intention(
    agent:,
    resource:,
    mode:,
    command_id: "cuc-advisory-requested-#{mode}-#{kind}"
  )
end

Then("agent B receives a modeled incompatible-intention result without a queue or preemption") do
  assert_acceptance_equal("completed", @advisory_requested.dig(:state, "result", "status"), "Contended Task status")
  assert_acceptance_equal(true, @advisory_requested.dig(:state, "result", "result", "isError"), "Contended Task error")
  assert_acceptance_equal("busy", @advisory_requested.dig(:outcome, "status"), "Contended semantic status")
  assert_acceptance_equal(
    "work_intention_conflict",
    @advisory_requested.dig(:outcome, "data", "code"),
    "Contended error code"
  )
  assert_acceptance(
    (@advisory_requested.fetch(:outcome).keys & %w[queue queued pending preempted]).empty?,
    "A contended result must not imply a queue or preemption"
  )
  existing_reference = advisory_intention_reference(@advisory_existing)
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared" ],
    work_intention_events(existing_reference.fetch("intention_id")).map(&:type),
    "Existing intention must not be preempted"
  )
end

Then("the result identifies every blocker with its resource, mode, owner, Attempt, purpose, context, and expiry") do
  blockers = @advisory_requested.dig(:outcome, "data", "details", "blockers")
  assert_acceptance_equal(1, blockers.length, "Unique blocker count")
  blocker = blockers.sole
  reference = advisory_intention_reference(@advisory_existing)
  assert_acceptance_equal(reference.fetch("intention_id"), blocker.fetch("intention_id"), "Blocker intention")
  assert_acceptance_equal(reference.fetch("resource_id"), blocker.fetch("resource_id"), "Blocker resource")
  assert_acceptance_equal(reference.fetch("resource_kind"), blocker.fetch("resource_kind"), "Blocker kind")
  assert_acceptance_equal(reference.fetch("resource_path"), blocker.fetch("resource_path"), "Blocker path")
  assert_acceptance_equal(@advisory_existing.fetch(:mode), blocker.fetch("mode"), "Blocker mode")
  assert_acceptance_equal(@advisory_existing.dig(:agent, :agent_id), blocker.fetch("owner_agent_id"), "Blocker owner")
  assert_acceptance_equal(@advisory_existing.dig(:agent, :attempt_id), blocker.fetch("owner_attempt_id"), "Blocker Attempt")
  assert_acceptance_equal(reference.fetch("purpose"), blocker.fetch("purpose"), "Blocker purpose")
  assert_acceptance_equal(reference.fetch("context"), blocker.fetch("context"), "Blocker context")
  assert_acceptance_equal(@advisory_existing.dig(:outcome, "data", "expires_at"), blocker.fetch("expires_at"), "Blocker expiry")
  assert_acceptance_equal(acceptance_repository_id, blocker.dig("scope", "repository_id"), "Blocker Repository")

  receipt = await_read_model("The rejected intention receipt to become available") do
    payload = call_tool("operation_get", { command_id: @advisory_requested.fetch(:command_id) })
      .dig("result", "structuredContent")
    [ payload["status"] == "busy", payload ]
  end
  assert_acceptance_equal(@advisory_requested.dig(:outcome, "data"), receipt.fetch("data"), "Rejection evidence")
end

Then("no partial intention set is recorded for agent B") do
  assert_acceptance_equal(nil, work_intention_set_state(advisory_agent("B").fetch(:attempt_id)), "Rejected intention set")
  assert_acceptance_equal(
    [],
    work_intention_events_for_command(@advisory_requested.fetch(:command_id)),
    "Rejected intention facts"
  )
  assert_command_rejected(@advisory_requested.fetch(:command_id))
end

Given("another agent has a shared intention with context explaining its current edit") do
  agent = advisory_agent("A")
  resource = advisory_resource("file", "curriculum/chapter-2.md", agent:)
  @advisory_existing = declare_advisory_intention(
    agent:,
    resource:,
    mode: "shared",
    command_id: "cuc-advisory-withdrawal-existing",
    purpose: "Correct one paragraph",
    context: "The paragraph changes preserve the chapter structure"
  )
end

When("agent A renews that intention twice and withdraws it while read projections are stopped") do
  stop_read_model_subscriptions
  agent = @advisory_existing.fetch(:agent)
  data = @advisory_existing.dig(:outcome, "data")
  @advisory_renewal_receipts = []
  previous_expiry = data.fetch("expires_at")
  [ 600, 900 ].each_with_index do |ttl_seconds, index|
    task_id = submit_and_execute(
      "work_intention_set_renew",
      client_id: agent.fetch(:client_id),
      command_id: "cuc-advisory-replay-renew-#{index}",
      actor: { kind: "agent", id: agent.fetch(:agent_id) },
      change_set_id: @advisory_existing.dig(:arguments, :change_set_id),
      work_item_id: agent.fetch(:work_item_id),
      attempt_id: agent.fetch(:attempt_id),
      intention_set_id: data.fetch("intention_set_id"),
      intentions: data.fetch("intentions").map { _1.slice("resource_id", "intention_id", "fencing_token") },
      ttl_seconds:
    )
    state = task_request("tasks/get", task_id, client_id: agent.fetch(:client_id))
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Renewal Task result")
    receipt = state.dig("result", "result", "structuredContent", "data")
    assert_acceptance_equal(previous_expiry, receipt.fetch("previous_expires_at"), "Immediately previous renewal deadline")
    @advisory_renewal_receipts << [ "cuc-advisory-replay-renew-#{index}", receipt ]
    @advisory_latest_expiry = receipt.fetch("expires_at")
    previous_expiry = @advisory_latest_expiry
  end
  withdraw_advisory_intention(@advisory_existing, command_id: "cuc-advisory-replay-withdraw")
end

Then("each renewal receipt retains its own previous and extended deadlines") do
  @advisory_renewal_receipts.each do |command_id, expected|
    receipt = await_read_model("The exact earlier renewal receipt to become available") do
      outcome = call_tool("operation_get", { command_id: }).dig("result", "structuredContent")
      [ outcome["status"] == "ok", outcome ]
    end
    assert_acceptance_equal(expected.fetch("previous_expires_at"), receipt.dig("data", "result", "previous_expires_at"), "Earlier renewal previous deadline")
    assert_acceptance_equal(expected.fetch("expires_at"), receipt.dig("data", "result", "expires_at"), "Earlier renewal extended deadline")
    assert_acceptance_equal(expected.fetch("intentions"), receipt.dig("data", "result", "intentions"), "Earlier renewal membership")
  end
end

Then("available Attempt context reflects the latest renewal and withdrawal") do
  attempt_id = @advisory_existing.dig(:agent, :attempt_id)
  context = await_read_model("Repeated intention renewals and withdrawal to become available") do
    payload = coordination_context(attempt_id:)
    attempt = payload.dig("data", "context", "attempts")&.find { _1.fetch("attempt_id") == attempt_id }
    observed = attempt&.fetch("work_intention_set")
    [ observed && observed["expires_at"] == @advisory_latest_expiry && observed["withdrawn_at"], payload ]
  end
  view = context.dig("data", "context", "attempts").find { _1.fetch("attempt_id") == attempt_id }.fetch("work_intention_set")
  assert_acceptance(@advisory_latest_expiry, "Latest renewal deadline")
  assert_acceptance(view.fetch("last_renewed_at"), "Latest renewal timestamp")
  assert_acceptance_equal(
    @advisory_existing.dig(:outcome, "data", "intention_set_id"), view.fetch("intention_set_id"), "Intention set identity"
  )
end

When("an agent requests an overlapping exclusive intention") do
  agent = advisory_agent("B")
  resource = advisory_resource("file", "curriculum/chapter-2.md", agent:)
  @advisory_requested = declare_advisory_intention(
    agent:,
    resource:,
    mode: "exclusive",
    command_id: "cuc-advisory-withdrawal-blocked",
    purpose: "Rewrite chapter translation",
    context: "The whole chapter may change"
  )
end

Then("the request fails immediately with that context and no pending reservation is created") do
  assert_acceptance_equal("busy", @advisory_requested.dig(:outcome, "status"), "Blocked exclusive status")
  assert_acceptance_equal(
    @advisory_existing.dig(:arguments, :resources).sole.fetch(:context),
    @advisory_requested.dig(:outcome, "data", "details", "blockers").sole.fetch("context"),
    "Blocker context"
  )
  assert_acceptance_equal(nil, work_intention_set_state(advisory_agent("B").fetch(:attempt_id)), "Pending set")
end

When("the existing agent withdraws its intention and the requester deliberately retries") do
  withdraw_advisory_intention(@advisory_existing, command_id: "cuc-advisory-withdrawal")
  @advisory_retry = declare_advisory_intention(
    agent: advisory_agent("B"),
    resource: @advisory_requested.fetch(:resource),
    mode: "exclusive",
    command_id: "cuc-advisory-withdrawal-retry",
    purpose: @advisory_requested.dig(:arguments, :resources).sole.fetch(:purpose),
    context: @advisory_requested.dig(:arguments, :resources).sole.fetch(:context)
  )
end

Then("the exclusive intention succeeds with a later fencing token") do
  assert_acceptance_equal("ok", @advisory_retry.dig(:outcome, "status"), "Retried exclusive status")
  previous = advisory_intention_reference(@advisory_existing).fetch("fencing_token")
  current = advisory_intention_reference(@advisory_retry).fetch("fencing_token")
  assert_acceptance(current > previous, "Retry must receive a later fencing token")
end

Given("an exclusive intention deadline has elapsed without an expiry projector update") do
  agent = advisory_agent("A")
  resource = advisory_resource("file", "app/models/expired.rb", agent:)
  @advisory_existing = declare_advisory_intention(
    agent:,
    resource:,
    mode: "exclusive",
    command_id: "cuc-advisory-expiry-existing",
    ttl_seconds: 30,
    purpose: "Short exclusive edit",
    context: "This intention may expire before its audit job runs"
  )
  expiry = Time.iso8601(@advisory_existing.dig(:outcome, "data", "expires_at"))
  eventually("the exclusive work intention deadline", timeout_seconds: 35) do
    now = Time.now.utc
    [ now > expiry, now ]
  end
  intention_id = advisory_intention_reference(@advisory_existing).fetch("intention_id")
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared" ],
    work_intention_events(intention_id).map(&:type),
    "Expiry projector must not have updated the intention"
  )
end

When("another agent deliberately declares an overlapping shared intention") do
  agent = advisory_agent("B")
  resource = advisory_resource("file", "app/models/expired.rb", agent:)
  @advisory_retry = declare_advisory_intention(
    agent:,
    resource:,
    mode: "shared",
    command_id: "cuc-advisory-expiry-retry",
    purpose: "Continue after the deadline",
    context: "The requester deliberately rechecks authoritative state"
  )
end

Then("the write side rebuilds current intention state from pg_eventstore") do
  assert_acceptance_equal(
    nil,
    Coordinator::Read::AttemptHistory.find_by(attempt_id: advisory_agent("A").fetch(:attempt_id)),
    "The command must not require an Attempt read model"
  )
  assert_command_succeeded(@advisory_retry.fetch(:command_id))
end

Then("the new intention succeeds without waiting for a read model or expiry audit") do
  assert_acceptance_equal("ok", @advisory_retry.dig(:outcome, "status"), "Post-deadline declaration")
  intention_id = advisory_intention_reference(@advisory_existing).fetch("intention_id")
  assert_acceptance_equal(
    [ "ResourceWorkIntentionDeclared" ],
    work_intention_events(intention_id).map(&:type),
    "Old intention remains an unprojected elapsed fact"
  )
end
