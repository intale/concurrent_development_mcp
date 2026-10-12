# frozen_string_literal: true

Given("agent A has a two-resource shared work-intention set") do
  @optimistic_renewal_agent = advisory_agent("A")
  agent = @optimistic_renewal_agent
  resources = [ "app/saga-one.rb", "app/saga-two.rb" ].map do |path|
    advisory_resource("file", path, agent:)
  end
  task_id = submit_and_execute("work_intention_set_declare", client_id: agent.fetch(:client_id),
    command_id: "cuc-optimistic-renewal-declare", actor: { kind: "agent", id: agent.fetch(:agent_id) },
    change_set_id: AdvisoryWorkIntentionAcceptanceWorld::ADVISORY_CHANGE_SET_ID,
    work_item_id: agent.fetch(:work_item_id), attempt_id: agent.fetch(:attempt_id), repository_id: acceptance_repository_id,
    base_commit_oid: AdvisoryWorkIntentionAcceptanceWorld::ADVISORY_BASE_COMMIT_OID,
    resources: resources.map { { resource_id: _1.fetch(:resource_id), mode: "shared", purpose: "Coordinate independent renewal steps" } },
    ttl_seconds: 300)
  @optimistic_renewal_set = task_request("tasks/get", task_id, client_id: agent.fetch(:client_id)).dig("result", "result", "structuredContent", "data")
end

When("agent A requests a renewal and withdraws the set after the first member commits") do
  agent = @optimistic_renewal_agent
  set = @optimistic_renewal_set
  gate, release = Queue.new, Queue.new
  armed = true
  trace = TracePoint.new(:call) do |frame|
    # Observe (never invoke) the command boundary to coordinate a real MCP race.
    next unless armed && frame.method_id == :call_command && frame.defined_class.name&.end_with?("::ExecuteRecordWorkIntentionRenewalOutcome")
    command = frame.binding.local_variable_get(:command)
    next unless command.actor.id == agent.fetch(:agent_id)
    armed = false
    gate << command.intention_id
    release.pop
  end
  @optimistic_renewal_arguments = {
    command_id: "cuc-optimistic-renewal-request", actor: { kind: "agent", id: agent.fetch(:agent_id) },
    change_set_id: AdvisoryWorkIntentionAcceptanceWorld::ADVISORY_CHANGE_SET_ID,
    work_item_id: agent.fetch(:work_item_id), attempt_id: agent.fetch(:attempt_id),
    intention_set_id: set.fetch("intention_set_id"),
    intentions: set.fetch("intentions").map { _1.slice("resource_id", "intention_id", "fencing_token") }, ttl_seconds: 900 }
  trace.enable
  @optimistic_renewal_task_id = call_tool("work_intention_set_renew", @optimistic_renewal_arguments,
    client_id: agent.fetch(:client_id)).dig("result", "taskId")
  start_process_subscriptions
  eventually("first renewal member to commit before its independent outcome") { [ !gate.empty?, nil ] }
  @optimistic_renewed_intention_id = gate.pop
  working = task_request("tasks/get", @optimistic_renewal_task_id, client_id: agent.fetch(:client_id))
  assert_acceptance_equal("working", working.dig("result", "status"), "In-progress renewal Task")
  submit_and_execute("work_intention_set_withdraw", client_id: agent.fetch(:client_id),
    command_id: "cuc-optimistic-renewal-withdraw", actor: @optimistic_renewal_arguments.fetch(:actor),
    change_set_id: @optimistic_renewal_arguments.fetch(:change_set_id), work_item_id: agent.fetch(:work_item_id),
    attempt_id: agent.fetch(:attempt_id), intention_set_id: set.fetch("intention_set_id"),
    intentions: @optimistic_renewal_arguments.fetch(:intentions))
  release << true
  trace.disable
  @optimistic_renewal_terminal = await_task_terminal(@optimistic_renewal_task_id, client_id: agent.fetch(:client_id))
ensure
  trace&.disable
  release << true if release
end

Then("the renewal Task completes with an accountable partial failure") do
  terminal = @optimistic_renewal_terminal.fetch("result")
  assert_acceptance_equal("completed", terminal.fetch("status"), "Terminal Task status")
  assert_acceptance_equal(true, terminal.dig("result", "isError"), "Partial-failure result")
  result = terminal.dig("result", "structuredContent")
  assert_acceptance_equal("failed", result.fetch("status"), "Canonical Saga status")
  assert_acceptance_equal("saga_execution_failed", result.dig("data", "code"), "Saga failure code")
  assert_acceptance_equal(true, result.dig("data", "details", "effects_committed"), "Committed partial effects")
  assert_acceptance_equal("work_intention_set_inactive", result.dig("data", "details", "reason_code"), "Lost liveness race")
end

Then("the first member keeps its committed extension while the second was not renewed") do
  agent = @optimistic_renewal_agent
  facts = work_intention_events_for_attempt(agent.fetch(:attempt_id)).select { _1.type == "ResourceWorkIntentionRenewed" }
  assert_acceptance_equal([ @optimistic_renewed_intention_id ], facts.map { _1.data.fetch("intention_id") }, "Only committed renewal")
  assert_acceptance(facts.sole.data.fetch("expires_at") > @optimistic_renewal_set.fetch("expires_at"), "First extension survived withdrawal")
end

Then("the renewal progress can be discovered using the returned Task ID") do
  agent = @optimistic_renewal_agent
  @optimistic_renewal_progress = await_read_model("terminal renewal Saga progress") do
    response = call_tool("work_intention_renewal_get", { task_id: @optimistic_renewal_task_id }, client_id: agent.fetch(:client_id))
    view = response.dig("result", "structuredContent", "data", "renewal")
    [ view && %w[completed failed].include?(view.fetch("status")), view ]
  end
  assert_acceptance_equal(@optimistic_renewal_task_id, @optimistic_renewal_progress.fetch("task_id"), "Discovered Task identity")
  members = @optimistic_renewal_progress.fetch("members")
  assert_acceptance_equal(2, members.length, "Renewal progress member count")
  expected = @optimistic_renewed_intention_id ? %w[completed failed] : %w[completed completed]
  assert_acceptance_equal(expected, members.map { _1.fetch("status") }, "Individual member outcomes")
end

Then("a stale failed renewal projection remains available") do
  stop_read_model_subscriptions
  response = call_tool("work_intention_renewal_get", { task_id: @optimistic_renewal_task_id }, client_id: @optimistic_renewal_agent.fetch(:client_id))
  assert_acceptance_equal("ok", response.dig("result", "structuredContent", "status"), "Available projection")
  assert_acceptance_equal(@optimistic_renewal_progress, response.dig("result", "structuredContent", "data", "renewal"), "Stable failed projection")
end

Then("replaying the exact renewal request returns the same failed Task") do
  response = call_tool("work_intention_set_renew", @optimistic_renewal_arguments, client_id: @optimistic_renewal_agent.fetch(:client_id))
  assert_acceptance_equal(@optimistic_renewal_task_id, response.dig("result", "taskId"), "Exact replay identity")
  replay = task_request("tasks/get", @optimistic_renewal_task_id, client_id: @optimistic_renewal_agent.fetch(:client_id))
  assert_acceptance_equal(@optimistic_renewal_terminal.dig("result", "result"), replay.dig("result", "result"), "Original terminal failure")
end

When("agent A requests a shorter renewal deadline for the two-resource set") do
  agent = @optimistic_renewal_agent
  set = @optimistic_renewal_set
  @optimistic_renewal_task_id = submit_and_execute("work_intention_set_renew", client_id: agent.fetch(:client_id),
    command_id: "cuc-optimistic-renewal-shorter", actor: { kind: "agent", id: agent.fetch(:agent_id) },
    change_set_id: AdvisoryWorkIntentionAcceptanceWorld::ADVISORY_CHANGE_SET_ID,
    work_item_id: agent.fetch(:work_item_id), attempt_id: agent.fetch(:attempt_id), intention_set_id: set.fetch("intention_set_id"),
    intentions: set.fetch("intentions").map { _1.slice("resource_id", "intention_id", "fencing_token") }, ttl_seconds: 30)
end

Then("the renewal Task completes successfully with two no-op member outcomes") do
  terminal = task_request("tasks/get", @optimistic_renewal_task_id, client_id: @optimistic_renewal_agent.fetch(:client_id))
  assert_acceptance_equal(false, terminal.dig("result", "result", "isError"), "No-op renewal result")
  facts = work_intention_events_for_attempt(@optimistic_renewal_agent.fetch(:attempt_id))
  assert_acceptance_equal([], facts.select { _1.type == "ResourceWorkIntentionRenewed" }, "No duplicate/no-op lifecycle facts")
end
