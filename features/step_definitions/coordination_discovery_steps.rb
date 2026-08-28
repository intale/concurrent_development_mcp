# frozen_string_literal: true

Given(
  "project scope {string} has active checkpointed coordination labeled {string}"
) do |scope, label|
  @discoverable_coordination = prepare_discoverable_coordination(
    scope:,
    label:,
    checkpoint: true
  )
end

When("clean agent {string} lists coordination using only that project scope") do |agent_id|
  scope = @discoverable_coordination.fetch(:scope)
  @coordination_discovery_used_tools = [ "coordination_list" ]
  @coordination_discovery_arguments = { scope: }
  @coordination_discovery_client_id = agent_id
  @coordination_discovery_payload = coordination_discovery_payload(scope:, client_id: agent_id)
end

Then("the agent discovers the active ChangeSet without a remembered coordination ID") do
  items = coordination_discovery_items(@coordination_discovery_payload)
  expected_id = @discoverable_coordination.dig(:ids, :change_set_id)
  assert_acceptance_equal([ :scope ], @coordination_discovery_arguments.keys, "Discovery arguments")
  assert_acceptance(
    items.any? { _1.fetch("change_set_id") == expected_id && _1.fetch("status") == "active" },
    "Exact project scope did not discover active ChangeSet #{expected_id}"
  )
end

Then("every discovered coordination action is executable through public MCP") do
  listed = mcp_request(
    method: "tools/list",
    params: {},
    client_id: @coordination_discovery_client_id
  ).dig("result", "tools").map { _1.fetch("name") }
  actions = @coordination_discovery_payload.fetch("next_actions")
  assert_acceptance(actions.any?, "Coordination discovery exposed no continuation action")
  assert_acceptance(
    actions.all? { listed.include?(_1.fetch("tool")) },
    "Coordination discovery exposed an unregistered public action: #{actions.inspect}"
  )
  @followed_coordination_contexts = follow_coordination_actions(
    @coordination_discovery_payload,
    client_id: @coordination_discovery_client_id
  )
  assert_acceptance(
    @followed_coordination_contexts.all? { _1.fetch("status") == "ok" },
    "A discovered coord_context action was not executable"
  )
end

Then("the followed context exposes its WorkItem and active Attempt") do
  context = @followed_coordination_contexts.sole.dig("data", "context")
  ids = @discoverable_coordination.fetch(:ids)
  assert_acceptance(
    context.fetch("work_items").any? { _1.fetch("work_item_id") == ids.fetch(:work_item_id) },
    "Followed context omitted WorkItem #{ids.fetch(:work_item_id)}"
  )
  assert_acceptance(
    context.fetch("attempts").any? do |attempt|
      attempt.fetch("attempt_id") == ids.fetch(:attempt_id) &&
        !%w[abandoned completed].include?(attempt.fetch("status"))
    end,
    "Followed context omitted active Attempt #{ids.fetch(:attempt_id)}"
  )
end

When("replacement agent {string} lists coordination using only that project scope") do |agent_id|
  scope = @discoverable_coordination.fetch(:scope)
  @coordination_discovery_used_tools = [ "coordination_list" ]
  @coordination_discovery_arguments = { scope: }
  @coordination_discovery_client_id = agent_id
  @coordination_discovery_payload = coordination_discovery_payload(scope:, client_id: agent_id)
  @followed_coordination_contexts = follow_coordination_actions(
    @coordination_discovery_payload,
    client_id: agent_id
  )
end

Then("the replacement reconstructs the ChangeSet, WorkItem, Attempt, and Candidate checkpoint") do
  ids = @discoverable_coordination.fetch(:ids)
  item = coordination_discovery_items(@coordination_discovery_payload).find do |candidate|
    candidate.fetch("change_set_id") == ids.fetch(:change_set_id)
  end
  assert_acceptance(item, "Replacement did not discover ChangeSet #{ids.fetch(:change_set_id)}")
  assert_acceptance_equal(1, item.fetch("candidate_checkpoint_count"), "Candidate checkpoint count")
  context = @followed_coordination_contexts.sole.dig("data", "context")
  assert_acceptance(
    context.fetch("work_items").any? { _1.fetch("work_item_id") == ids.fetch(:work_item_id) },
    "Replacement context omitted the WorkItem"
  )
  assert_acceptance(
    context.fetch("attempts").any? { _1.fetch("attempt_id") == ids.fetch(:attempt_id) },
    "Replacement context omitted the Attempt"
  )
  assert_acceptance(
    context.fetch("candidate_checkpoints").any? do |checkpoint|
      checkpoint.fetch("candidate_id") == @discoverable_coordination.fetch(:candidate_id)
    end,
    "Replacement context omitted the Candidate checkpoint"
  )
end

Then("no Task enumeration or local build file is required") do
  assert_acceptance_equal(
    %w[coordination_list coord_context],
    @coordination_discovery_used_tools.uniq,
    "Resume discovery tools"
  )
  assert_acceptance_equal([ :scope ], @coordination_discovery_arguments.keys, "Resume inputs")
end

Given(
  "project scopes {string} and {string} each coordinate local label {string}"
) do |first_scope, second_scope, label|
  @scoped_discovery_label = label
  @scoped_discoveries = [ first_scope, second_scope ].to_h do |scope|
    [ scope, prepare_discoverable_coordination(scope:, label:) ]
  end
end

When("clean agents list coordination for their own exact project scopes") do
  @scoped_discovery_payloads = @scoped_discoveries.keys.to_h do |scope|
    client_id = "clean-#{@scoped_discoveries.fetch(scope).fetch(:suffix)}"
    [ scope, coordination_discovery_payload(scope:, client_id:) ]
  end
end

Then(
  "each scope returns one distinct canonical ChangeSet for local label {string}"
) do |label|
  assert_acceptance_equal(@scoped_discovery_label, label, "Reusable local label")
  items = @scoped_discovery_payloads.transform_values { coordination_discovery_items(_1) }
  assert_acceptance(items.values.all?(&:one?), "Each exact scope must expose exactly one coordination")
  change_set_ids = items.values.map { _1.sole.fetch("change_set_id") }
  assert_acceptance_equal(2, change_set_ids.uniq.length, "Canonical ChangeSet identity count")
  assert_acceptance(
    items.values.flatten.all? { _1.fetch("goal").include?(label) },
    "Reusable local label is not visible as human context"
  )
end

Then("neither scoped result exposes the other project's WorkItem or Attempt") do
  @scoped_discoveries.each do |scope, coordination|
    item = coordination_discovery_items(@scoped_discovery_payloads.fetch(scope)).sole
    own_ids = coordination.fetch(:ids)
    other_ids = @scoped_discoveries.reject { |candidate_scope, _| candidate_scope == scope }
      .values.sole.fetch(:ids)
    assert_acceptance_equal([ own_ids.fetch(:work_item_id) ], item.fetch("work_item_ids"), "Scoped WorkItems")
    assert_acceptance_equal([ own_ids.fetch(:attempt_id) ], item.fetch("active_attempt_ids"), "Scoped Attempts")
    assert_acceptance(
      !item.fetch("work_item_ids").include?(other_ids.fetch(:work_item_id)) &&
        !item.fetch("active_attempt_ids").include?(other_ids.fetch(:attempt_id)),
      "Scoped discovery leaked the other project's coordination"
    )
  end
end

Given(
  "project scope {string} has projected active coordination labeled {string}"
) do |scope, label|
  @stale_discovery_coordination = prepare_discoverable_coordination(
    scope:,
    label:,
    reserve: true
  )
  @stale_discovery_before = coordination_discovery_payload(
    scope:,
    client_id: "stale-reader"
  )
end

When("its read-model subscriptions pause and a Candidate checkpoint commits through MCP") do
  stop_read_model_subscriptions
  submit_discovery_candidate(@stale_discovery_coordination)
  @stale_discovery_during = coordination_discovery_payload(
    scope: @stale_discovery_coordination.fetch(:scope),
    client_id: "stale-reader"
  )
end

Then("scoped discovery still serves the previously projected coordination") do
  before = coordination_discovery_items(@stale_discovery_before).sole
  during = coordination_discovery_items(@stale_discovery_during).sole
  assert_acceptance_equal(before, during, "Available stale coordination")
  assert_acceptance_equal(0, during.fetch("candidate_checkpoint_count"), "Stale checkpoint count")
end

When("read-model subscriptions restart") do
  restart_read_model_subscriptions
end

Then("scoped discovery eventually includes the Candidate checkpoint") do
  expected_candidate_id = @stale_discovery_coordination.fetch(:candidate_id)
  @stale_discovery_converged = eventually("Candidate checkpoint to become discoverable") do
    payload = coordination_discovery_payload(
      scope: @stale_discovery_coordination.fetch(:scope),
      client_id: "stale-reader"
    )
    item = coordination_discovery_items(payload).sole
    context = call_tool(
      "coord_context",
      { change_set_id: item.fetch("change_set_id") },
      client_id: "stale-reader"
    ).dig("result", "structuredContent", "data", "context")
    observed = item.fetch("candidate_checkpoint_count") == 1 &&
               context.fetch("candidate_checkpoints").any? do |checkpoint|
                 checkpoint.fetch("candidate_id") == expected_candidate_id
               end
    [ observed, payload ]
  end
  assert_acceptance_equal(
    1,
    coordination_discovery_items(@stale_discovery_converged).sole.fetch("candidate_checkpoint_count"),
    "Converged checkpoint count"
  )
end

Given(
  "project scope {string} has an active {string} Decision"
) do |scope, topic_id|
  assert_acceptance_equal("candidate.impact_policy", topic_id, "Discovery topic")
  @decision_discovery_coordination = prepare_discoverable_coordination(
    scope:,
    label: "decision-topics"
  )
  activate_discovery_impact_policy(@decision_discovery_coordination)
end

When("a clean agent lists active Decisions for that Repository and topic") do
  @decision_discovery_payload = call_tool(
    "decision_list",
    {
      repository_id: @decision_discovery_coordination.fetch(:repository_id),
      topic_id: "candidate.impact_policy",
      policy_status: "active"
    },
    client_id: "clean-decision-agent"
  ).dig("result", "structuredContent")
end

Then("the non-testing Decision is discoverable with an executable detail action") do
  decision_id = @decision_discovery_coordination.fetch(:decision_id)
  items = @decision_discovery_payload.dig("data", "page", "items") || []
  assert_acceptance_equal([ decision_id ], items.map { _1.fetch("decision_id") }, "Discovered Decision")
  action = @decision_discovery_payload.fetch("next_actions").sole
  assert_acceptance_equal("decision_get", action.fetch("tool"), "Decision detail tool")
  detail = call_tool(
    action.fetch("tool"),
    action.fetch("arguments"),
    client_id: "clean-decision-agent"
  ).dig("result", "structuredContent")
  assert_acceptance_equal("ok", detail.fetch("status"), "Decision detail status")
  assert_acceptance_equal(decision_id, detail.dig("data", "decision", "decision_id"), "Decision detail")
end

Then("resolving {string} returns that exact effective Decision") do |topic_id|
  decision_id = @decision_discovery_coordination.fetch(:decision_id)
  payload = await_read_model("Decision #{decision_id} to resolve") do
    current = call_tool(
      "decision_resolve",
      {
        topic_id:,
        context: discovery_decision_context(@decision_discovery_coordination)
      },
      client_id: "clean-decision-agent"
    ).dig("result", "structuredContent")
    observed = current.dig(
      "data",
      "decision_context",
      "document",
      "effective_decision",
      "head",
      "decision_id"
    )
    [ current.fetch("status") == "ok" && observed == decision_id, current ]
  end
  assert_acceptance_equal(
    decision_id,
    payload.dig(
      "data",
      "decision_context",
      "document",
      "effective_decision",
      "head",
      "decision_id"
    ),
    "Resolved Decision"
  )
end
