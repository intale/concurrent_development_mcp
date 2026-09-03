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
        repository_ids: [ acceptance_repository_id ],
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
    %w[CommandRegistered CommandSucceeded],
    command_events(@decision_activation.fetch(:activation_command_id)).map(&:type),
    "Decision activation command lifecycle"
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
    [ "repo:#{acceptance_repository_id}:testing" ],
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

Then("the losing activation writes no Decision facts and records its command rejection") do
  assert_acceptance_equal(
    [],
    decision_events(@losing_activation.fetch(:decision_id)),
    "Losing Decision facts"
  )
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@losing_activation.fetch(:activation_command_id)).map(&:type),
    "Losing command lifecycle"
  )
  assert_acceptance_equal(
    2,
    decision_events(@winning_activation.fetch(:decision_id)).length,
    "Winning Decision facts"
  )
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(@winning_activation.fetch(:activation_command_id)).map(&:type),
    "Winning command lifecycle"
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
    %w[CommandRegistered CommandSucceeded],
    command_events(@decision_correction.fetch(:command_id)).map(&:type),
    "Decision correction command lifecycle"
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
    %w[CommandRegistered CommandRejected],
    command_events(@stale_decision_correction.fetch(:command_id)).map(&:type),
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
