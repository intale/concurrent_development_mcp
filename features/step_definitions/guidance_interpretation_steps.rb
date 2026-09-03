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
      repository_ids: [ acceptance_repository_id ],
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
    %w[CommandRegistered CommandRejected],
    command_events(@duplicate_guidance_command_id).map(&:type),
    "Duplicate guidance command lifecycle"
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
      repository_ids: [ acceptance_repository_id ],
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
    %w[CommandRegistered CommandSucceeded],
    command_events("cmd-cuc-interpretation-b").map(&:type),
    "Hard proposal command lifecycle"
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
