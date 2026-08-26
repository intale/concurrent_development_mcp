Given(
  "agent {string} has active Attempt {string} for WorkItem {string} in ChangeSet {string} and repository {string}"
) do |agent_id, attempt_id, work_item_id, change_set_id, repository_label|
  repository_id = register_acceptance_repository(repository_label)
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
  choice = record_testing_framework_choice(choice_id:, option_id:)
  @choice_id = choice.fetch(:choice_id)
  @choice_command_id = choice.fetch(:command_id)
  @choice_task_id = choice.fetch(:task_id)
  @choice_task_state = choice.fetch(:state)
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

When("the agent follows the refresh action for the current Decision context") do
  decision_id = @decision_activation_candidates.sole.fetch(:decision_id)
  stale_digest = @choice_decision_context.fetch("digest")
  project_decision_recorded(decision_id)
  project_remaining_decision_facts(decision_id)
  payload = call_tool(
    "decision_resolve",
    { topic_id: "testing.framework", context: @choice_context }
  ).dig("result", "structuredContent")

  assert_acceptance_equal("ok", payload.fetch("status"), "Refreshed Decision context")
  @choice_decision_context = payload.dig("data", "decision_context")
  assert_acceptance(
    @choice_decision_context.fetch("digest") != stale_digest,
    "The refreshed context must bind the current Decision head"
  )
end

Then("the current testing-framework policy is available") do
  decision = @choice_decision_context.dig("document", "effective_decision")
  assert_acceptance(decision, "The refreshed context has no effective Decision")
  assert_acceptance_equal("testing.framework", decision.fetch("topic_id"), "Decision topic")
end

When("the accepted AgentChoice {string} reaches the read side") do |choice_id|
  project_agent_choice_event(choice_id, "AgentChoiceRecorded")
  project_agent_choice_event(choice_id, "AgentChoiceAccepted")
end

When(
  "the host activates active-attempt Decision {string} requiring {string} through Tasks"
) do |decision_id, option_id|
  @impact_decision_id = decision_id
  @impact_source = activate_impact_decision(
    decision_id:,
    option_id:,
    available: false
  )
end

Given(
  "active-attempt Decision {string} requiring {string} is active and available"
) do |decision_id, option_id|
  @impact_decision_id = decision_id
  @impact_source = activate_impact_decision(
    decision_id:,
    option_id:,
    available: true
  )
end

When(
  "the host corrects Decision {string} to advisory active-attempt choice {string} through Tasks"
) do |decision_id, option_id|
  @impact_source = correct_impact_decision(decision_id:, option_id:)
end

When("the impact Saga processes and redrives the Decision change") do
  @impact_saga = drive_impact_saga(@impact_source)
end

Then(
  "one invalidating assessment and one terminal invalidation are durable for {string}"
) do |choice_id|
  assessment = impact_assessment_event(choice_id)
  assert_acceptance(assessment, "AgentChoice #{choice_id} has no impact assessment")
  payload = impact_payload(assessment)
  invalidations = impact_choice_events(choice_id).select do |event|
    event.type == "AgentChoiceInvalidatedByDecision"
  end
  assert_acceptance_equal("invalidated", payload.assessment.outcome, "Impact outcome")
  assert_acceptance_equal("blocking_policy_introduced", payload.assessment.reason, "Impact reason")
  assert_acceptance_equal(1, invalidations.length, "Terminal invalidation count")
  assert_acceptance_equal(@impact_saga.fetch(:started).id, assessment.causation_id, "Assessment parent")
  assert_acceptance_equal(
    @impact_saga.fetch(:started).id,
    invalidations.sole.causation_id,
    "Invalidation parent"
  )
  assert_acceptance_equal(@impact_source.correlation_id, assessment.correlation_id, "Saga correlation")
end

Then(
  "Attempt {string} has no projected impacts while AgentChoice {string} remains accepted"
) do |attempt_id, choice_id|
  page = impact_page(attempt_id:)
  choice = agent_choice_view(choice_id).dig("data", "choice")
  assert_acceptance_equal([], page.fetch("items"), "Unprojected impact page")
  assert_acceptance_equal(false, page.fetch("has_more"), "Unprojected impact continuation")
  assert_acceptance_equal("accepted", choice.fetch("observation_status"), "Lagging Choice status")
end

When("the impact assessment for {string} reaches the read side") do |choice_id|
  project_impact_assessment(choice_id)
end

Then(
  "Attempt {string} exposes the invalidating assessment while AgentChoice {string} remains accepted"
) do |attempt_id, choice_id|
  item = impact_page(attempt_id:).fetch("items").sole
  choice = agent_choice_view(choice_id).dig("data", "choice")
  assert_acceptance_equal(choice_id, item.fetch("choice_id"), "Impact Choice ID")
  assert_acceptance_equal("invalidated", item.fetch("outcome"), "Projected impact outcome")
  assert_acceptance_equal("guidance-host", item.dig("source_actor", "id"), "Decision source actor")
  assert_acceptance_equal(
    "agent-choice-decision-impact",
    item.dig("assessment_evidence", "actor", "id"),
    "Assessment actor"
  )
  assert_acceptance_equal("accepted", choice.fetch("observation_status"), "Independently lagging Choice")
  assert_acceptance(
    (choice.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "Lagging Choice must not expose a freshness gate"
  )
end

When("the invalidation for AgentChoice {string} reaches the read side") do |choice_id|
  project_choice_invalidation(choice_id)
end

Then(
  "AgentChoice {string} is invalidated and tells the agent to resolve current Decisions"
) do |choice_id|
  payload = agent_choice_view(choice_id)
  choice = payload.dig("data", "choice")
  action = payload.fetch("next_actions").sole
  assert_acceptance_equal("invalidated", choice.fetch("observation_status"), "Choice status")
  assert_acceptance_equal("blocking_policy_introduced", choice.dig("invalidation", "reason"), "Invalidation")
  assert_acceptance_equal("decision_resolve", action.fetch("tool"), "Recovery tool")
  assert_acceptance_equal("testing.framework", action.dig("arguments", "topic_id"), "Recovery topic")
  assert_acceptance(
    (choice.keys & %w[active fresh pending projection_status stream_revision]).empty?,
    "Invalidated Choice must not expose a freshness gate"
  )
end

Then(
  "one still-valid assessment and no invalidation are durable for {string}"
) do |choice_id|
  assessment = impact_assessment_event(choice_id)
  assert_acceptance(assessment, "AgentChoice #{choice_id} has no impact assessment")
  payload = impact_payload(assessment)
  invalidations = impact_choice_events(choice_id).select do |event|
    event.type == "AgentChoiceInvalidatedByDecision"
  end
  assert_acceptance_equal("still_valid", payload.assessment.outcome, "Impact outcome")
  assert_acceptance_equal("compliant_or_advisory", payload.assessment.reason, "Impact reason")
  assert_acceptance_equal([], invalidations, "Compatible Choice invalidations")
end

Then(
  "Attempt {string} exposes a still-valid assessment and AgentChoice {string} remains accepted"
) do |attempt_id, choice_id|
  item = impact_page(attempt_id:).fetch("items").sole
  choice = agent_choice_view(choice_id).dig("data", "choice")
  assert_acceptance_equal(choice_id, item.fetch("choice_id"), "Impact Choice ID")
  assert_acceptance_equal("still_valid", item.fetch("outcome"), "Impact outcome")
  assert_acceptance_equal("accepted", choice.fetch("observation_status"), "Compatible Choice status")
  assert_acceptance_equal(nil, choice.fetch("invalidation"), "Compatible Choice invalidation")
end

When(
  "the agent records {int} testing-framework choices starting at {string} through Tasks"
) do |count, prefix|
  @impact_choices = Array.new(count) do |index|
    record_testing_framework_choice(
      choice_id: "#{prefix}-#{index + 1}",
      option_id: "rspec"
    )
  end
end

Then("all impact-test choices have accepted authoritative facts") do
  @impact_choices.each do |choice|
    state = choice.fetch(:state)
    choice_id = choice.fetch(:choice_id)
    assert_acceptance_equal("completed", state.dig("result", "status"), "Choice Task status")
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Choice Task error")
    assert_acceptance_equal(
      %w[AgentChoiceRecorded AgentChoiceAccepted],
      impact_choice_events(choice_id).map(&:type),
      "Authoritative Choice facts"
    )
  end
end

When("all impact-test AgentChoices reach the read side") do
  @impact_choices.each do |choice|
    choice_id = choice.fetch(:choice_id)
    project_agent_choice_event(choice_id, "AgentChoiceRecorded")
    project_agent_choice_event(choice_id, "AgentChoiceAccepted")
  end
end

Then("every impact-test Choice has one assessment and one invalidation") do
  @impact_choices.each do |choice|
    choice_id = choice.fetch(:choice_id)
    assessment = impact_assessment_event(choice_id)
    invalidations = impact_choice_events(choice_id).count do |event|
      event.type == "AgentChoiceInvalidatedByDecision"
    end
    assert_acceptance(assessment, "AgentChoice #{choice_id} has no assessment")
    assert_acceptance_equal(1, invalidations, "AgentChoice #{choice_id} invalidations")
  end
end

When("all impact-test assessments reach the read side") do
  @impact_choices.each do |choice|
    choice_id = choice.fetch(:choice_id)
    project_impact_assessment(choice_id)
    project_impact_assessment(choice_id)
  end
end

Then(
  "the agent retrieves every impact once in two-item pages for Attempt {string}"
) do |attempt_id|
  first = impact_page(attempt_id:, limit: 2)
  second = impact_page(
    attempt_id:,
    after_global_position: first.fetch("next_global_position"),
    limit: 2
  )
  expected = @impact_choices.map { _1.fetch(:choice_id) }
  observed = [ *first.fetch("items"), *second.fetch("items") ].map { _1.fetch("choice_id") }
  assert_acceptance_equal(true, first.fetch("has_more"), "First impact-page continuation")
  assert_acceptance(first.fetch("next_global_position"), "First impact page has no cursor")
  assert_acceptance_equal(false, second.fetch("has_more"), "Final impact-page continuation")
  assert_acceptance_equal(nil, second.fetch("next_global_position"), "Final impact cursor")
  assert_acceptance_equal(expected, observed, "Paginated impact Choice IDs")
  assert_acceptance_equal(observed, observed.uniq, "Paginated impacts must not duplicate")
end
