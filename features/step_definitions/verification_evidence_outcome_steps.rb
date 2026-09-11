# frozen_string_literal: true

Given(
  "agent {string} actively claims Rails verification obligation {string}"
) do |agent_id, prefix|
  prepare_claimed_verification_obligation(prefix:, agent_id:)
end

Given(
  "agent {string} actively claims Rails verification obligation {string} with its claim available"
) do |agent_id, prefix|
  prepare_claimed_verification_obligation(prefix:, agent_id:, project_claim: true)
end

Given(
  "agent {string} claims Rails verification obligation {string} for {int} seconds"
) do |agent_id, prefix, duration|
  prepare_claimed_verification_obligation(
    prefix:,
    agent_id:,
    claim_duration: duration
  )
end

When(
  "the claimant submits {string} {string} evidence as command {string}"
) do |conclusion, evidence_kind, command_id|
  attempt = submit_evidence_attempt(command_id:, evidence_kind:, conclusion:)
  execute_evidence_attempt(attempt)
  @evidence_attempts ||= []
  @evidence_attempts << attempt
  @current_evidence_attempt = attempt
  @original_evidence_attempt ||= attempt
end

Then("the evidence Task completes with obligation status {string}") do |status|
  assert_evidence_task_status(@current_evidence_attempt, status)
end

Then("one attributed evidence fact and no terminal fact are durable") do
  evidence = compatibility_evidence_events.sole
  assessment = evidence.data.fetch("assessment")
  assert_acceptance_equal("VerificationEvidenceSubmitted", evidence.type, "Evidence fact")
  assert_acceptance_equal(@evidence_actor_id, evidence.metadata.fetch("actor_id"), "Evidence actor")
  assert_acceptance_equal(
    "cucumber-external-verifier",
    assessment.dig("producer", "name"),
    "Evidence producer"
  )
  assert_acceptance_equal([], verification_terminal_events, "Partial terminal facts")
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(@current_evidence_attempt.fetch(:command_id)).map(&:type),
    "Partial command lifecycle"
  )
end

Then("two attributed evidence facts and one satisfied fact are durable") do
  start_process_subscriptions
  evidence = compatibility_evidence_events
  terminal = eventually("Verification evidence satisfaction Saga to complete") do
    events = verification_terminal_events
    [ events.one?, events ]
  end.sole
  assert_acceptance_equal(2, evidence.length, "Satisfied evidence facts")
  assert_acceptance_equal(
    %w[combined_tests contract_compatibility_review],
    evidence.map { _1.data.fetch("evidence_kind") },
    "Satisfied evidence kinds"
  )
  assert_acceptance_equal(
    "VerificationObligationSatisfied",
    terminal.type,
    "Satisfied terminal fact"
  )
  assert_acceptance_equal(
    evidence.map { _1.data.fetch("evidence_id") },
    verification_selection_events.map { _1.data.fetch("evidence_id") },
    "Satisfied evidence selection"
  )
end

Then("the final evidence, outcome, command terminal, and Task carry exact tracing") do
  assert_evidence_task_tracing(@current_evidence_attempt)
end

Then("one attributed evidence fact and one failed fact are durable") do
  start_process_subscriptions
  evidence = compatibility_evidence_events.sole
  terminal = eventually("Verification evidence failure Saga to complete") do
    events = verification_terminal_events
    [ events.one?, events ]
  end.sole
  assert_acceptance_equal("failed", evidence.data.dig("assessment", "conclusion"), "Failed conclusion")
  assert_acceptance_equal("VerificationObligationFailed", terminal.type, "Failed terminal fact")
  assert_acceptance_equal(
    evidence.data.fetch("evidence_id"),
    verification_selection_events.sole.data.fetch("evidence_id"),
    "Failure evidence selection"
  )
  assert_acceptance_equal("submitted_evidence_failed", terminal.data.fetch("reason"), "Failure reason")
end

Then("the evidence result remains an attributed report rather than an execution claim") do
  attempt = @current_evidence_attempt
  evidence = evidence_event_for(attempt)
  result_data = attempt.dig(:content, "data")
  assessment = evidence.data.fetch("assessment")
  assert_acceptance_equal(
    attempt.dig(:arguments, :assessment, :producer, :name),
    assessment.dig("producer", "name"),
    "Attributed producer"
  )
  assert_acceptance_equal(
    attempt.dig(:arguments, :assessment, :run_id),
    assessment.fetch("run_id"),
    "Attributed run"
  )
  assert_acceptance_equal("failed", result_data.fetch("conclusion"), "Attributed conclusion")
  unsupported = %w[executed authenticated verified merge_safe work_completed]
  assert_acceptance_equal([], result_data.keys & unsupported, "Execution claims in result")
  assert_acceptance_equal([], evidence.data.keys & unsupported, "Execution claims in evidence")
end

Then("both nonterminal evidence Tasks complete with an open obligation") do
  attempts = @evidence_attempts.last(2)
  assert_acceptance_equal(2, attempts.length, "Nonterminal Tasks")
  attempts.each { assert_evidence_task_status(_1, "open") }
end

Then("two explanatory evidence facts and no terminal fact are durable") do
  evidence = compatibility_evidence_events
  assert_acceptance_equal(2, evidence.length, "Nonterminal evidence facts")
  assert_acceptance_equal(
    %w[inconclusive not_applicable],
    evidence.map { _1.data.dig("assessment", "conclusion") },
    "Nonterminal conclusions"
  )
  assert_acceptance(
    evidence.all? { _1.data.dig("assessment", "findings").any? },
    "Nonterminal evidence lacks findings"
  )
  assert_acceptance_equal([], verification_terminal_events, "Nonterminal outcome facts")
end

When("agent {string} reclaims the obligation after expiry") do |agent_id|
  @prior_evidence_claim = @evidence_claim
  @prior_evidence_actor_id = @evidence_actor_id
  expiry = Time.iso8601(@prior_evidence_claim.fetch("expires_at"))
  eventually("Prior verification claim to expire", timeout_seconds: 35) do
    now = Time.now.utc
    [ now >= expiry, now.iso8601(6) ]
  end
  attempt = submit_verification_obligation_claim(
    agent_id:,
    command_id: "cmd-cuc-evidence-reclaim-#{@obligation_prefix.downcase}",
    duration: 300
  )
  execute_verification_obligation_claim(attempt)
  assert_acceptance_equal(false, attempt.dig(:result, "isError"), "Evidence reclaim")
  @evidence_claim = attempt.dig(:content, "data")
  @evidence_actor_id = agent_id
  assert_acceptance_equal(
    @prior_evidence_claim.fetch("fencing_token") + 1,
    @evidence_claim.fetch("fencing_token"),
    "Reclaim fencing token"
  )
end

When("the prior claimant submits evidence with the stale fence") do
  @stale_evidence_attempt = submit_evidence_attempt(
    command_id: "cmd-cuc-evidence-stale-#{@obligation_prefix.downcase}",
    evidence_kind: "combined_tests",
    conclusion: "passed",
    actor_id: @prior_evidence_actor_id,
    claim: @prior_evidence_claim
  )
  execute_evidence_attempt(@stale_evidence_attempt)
end

Then("the stale evidence Task reports {string} without target facts") do |code|
  assert_evidence_task_error(@stale_evidence_attempt, code)
  assert_acceptance_equal([], compatibility_evidence_events, "Stale evidence facts")
  assert_acceptance_equal([], verification_terminal_events, "Stale terminal facts")
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@stale_evidence_attempt.fetch(:command_id)).map(&:type),
    "Stale command lifecycle"
  )
end

When("the exact evidence command is submitted again") do
  original = @original_evidence_attempt
  response = call_tool("compatibility_assessment_submit", original.fetch(:arguments))
  @replayed_evidence_attempt = {
    command_id: original.fetch(:command_id),
    arguments: original.fetch(:arguments),
    task_id: response.dig("result", "taskId"),
    submitted_response: response,
    replay_of: original
  }
  execute_evidence_attempt(@replayed_evidence_attempt)
end

Then("both evidence responses expose the same Task result and one evidence fact") do
  original = @original_evidence_attempt
  replay = @replayed_evidence_attempt
  assert_acceptance_equal(original.fetch(:task_id), replay.fetch(:task_id), "Replayed Task identity")
  assert_evidence_task_status(original, "open")
  assert_evidence_task_status(replay, "open")
  assert_acceptance_equal(original.fetch(:content), replay.fetch(:content), "Evidence replay result")
  assert_acceptance_equal(1, compatibility_evidence_events.length, "Replayed evidence facts")
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(original.fetch(:command_id)).map(&:type),
    "Replayed command lifecycle"
  )
end

When("the same assessment is submitted as new command {string}") do |command_id|
  original = @original_evidence_attempt
  arguments = original.fetch(:arguments).merge(command_id:)
  response = call_tool("compatibility_assessment_submit", arguments)
  @duplicate_evidence_attempt = {
    command_id:,
    arguments:,
    task_id: response.dig("result", "taskId"),
    submitted_response: response
  }
  execute_evidence_attempt(@duplicate_evidence_attempt)
end

Then("the duplicate evidence Task reports {string} with a rejected command lifecycle") do |code|
  assert_evidence_task_error(@duplicate_evidence_attempt, code)
  assert_acceptance_equal(1, compatibility_evidence_events.length, "Duplicate evidence facts")
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@duplicate_evidence_attempt.fetch(:command_id)).map(&:type),
    "Duplicate command lifecycle"
  )
end

When("the claimant executes both required evidence Tasks concurrently") do
  @concurrent_evidence_attempts = [
    submit_evidence_attempt(
      command_id: "cmd-cuc-evidence-race-tests",
      evidence_kind: "combined_tests",
      conclusion: "passed"
    ),
    submit_evidence_attempt(
      command_id: "cmd-cuc-evidence-race-contract",
      evidence_kind: "contract_compatibility_review",
      conclusion: "passed"
    )
  ]
  @concurrent_evidence_attempts.map do |attempt|
    Thread.new { execute_task(attempt.fetch(:task_id)) }
  end.each(&:value)
  @concurrent_evidence_attempts.each { capture_evidence_attempt(_1) }
end

Then("both evidence Tasks succeed with open submission results") do
  @concurrent_evidence_attempts.each do |attempt|
    assert_acceptance_equal("completed", attempt.dig(:state, "result", "status"), "Race Task status")
    assert_acceptance_equal(false, attempt.dig(:result, "isError"), "Race Task error")
  end
  assert_acceptance_equal(
    %w[open open],
    @concurrent_evidence_attempts.map { _1.dig(:content, "data", "status") }.sort,
    "Race results"
  )
end

Then("exactly two evidence facts and one satisfied fact are durable") do
  assert_acceptance_equal(2, compatibility_evidence_events.length, "Concurrent evidence facts")
  start_process_subscriptions
  terminal = eventually("Concurrent verification satisfaction Saga to complete") do
    events = verification_terminal_events
    [ events.one?, events ]
  end.sole
  assert_acceptance_equal("VerificationObligationSatisfied", terminal.type, "Concurrent outcome")
  lifecycle_facts = @concurrent_evidence_attempts.sum do |attempt|
    command_events(attempt.fetch(:command_id)).length
  end
  assert_acceptance_equal(4, lifecycle_facts, "Concurrent command lifecycle facts")
end

When("both passed assessments commit without projecting their evidence") do
  @lag_evidence_attempts = [
    submit_evidence_attempt(
      command_id: "cmd-cuc-evidence-view-tests",
      evidence_kind: "combined_tests",
      conclusion: "passed"
    ),
    submit_evidence_attempt(
      command_id: "cmd-cuc-evidence-view-contract",
      evidence_kind: "contract_compatibility_review",
      conclusion: "passed"
    )
  ]
  @lag_evidence_attempts.each { execute_evidence_attempt(_1) }
  assert_acceptance_equal(2, compatibility_evidence_events.length, "Lag source evidence")
  start_process_subscriptions
  eventually("Lagging-view verification outcome to become durable") do
    events = verification_terminal_events
    [ events.one?, events.map(&:type) ]
  end
end

Then("the available view still reports open with no observed evidence") do
  content = candidate_obligation_page(obligation_id: @obligation_id)
  item = content.dig("data", "page", "items").sole
  assert_acceptance_equal("ok", content.fetch("status"), "Lagging evidence query")
  assert_acceptance_equal("open", item.fetch("status"), "Lagging evidence status")
  assert_acceptance_equal(
    {
      "required_evidence_kinds" => %w[combined_tests contract_compatibility_review],
      "passed_evidence_kinds" => [],
      "missing_evidence_kinds" => %w[combined_tests contract_compatibility_review],
      "evidence_count" => 0
    },
    item.fetch("progress"),
    "Lagging evidence progress"
  )
  assert_acceptance_equal([], item.fetch("submitted_evidence"), "Lagging submitted evidence")
  assert_acceptance_equal(nil, item.fetch("outcome"), "Lagging outcome")
  freshness = %w[fresh pending projection_status stream_revision]
  assert_acceptance_equal([], content.keys & freshness, "Lagging freshness gate")
end

When("the evidence and outcome reach the read side after a subscription restart") do
  facts = verification_obligation_history.select do |event|
    event.type.in?(%w[VerificationEvidenceSubmitted VerificationObligationSatisfied])
  end
  assert_acceptance_equal(3, facts.length, "Evidence and outcome facts")
  project_verification_events(facts, redeliver: true)
end

Then("the available view reports satisfied with complete attributed evidence") do
  content = candidate_obligation_page(obligation_id: @obligation_id, status: "satisfied")
  item = content.dig("data", "page", "items").sole
  assert_acceptance_equal("satisfied", item.fetch("status"), "Converged evidence status")
  assert_acceptance_equal(
    %w[combined_tests contract_compatibility_review],
    item.dig("progress", "passed_evidence_kinds"),
    "Converged passed evidence"
  )
  assert_acceptance_equal([], item.dig("progress", "missing_evidence_kinds"), "Converged missing evidence")
  assert_acceptance_equal(2, item.dig("progress", "evidence_count"), "Converged evidence count")
  evidence = item.fetch("submitted_evidence")
  assert_acceptance_equal(2, evidence.length, "Converged evidence rows")
  assert_acceptance(
    evidence.all? { _1.dig("assessment", "producer", "name") == "cucumber-external-verifier" },
    "Converged evidence attribution"
  )
  assert_acceptance(item.fetch("outcome"), "Converged outcome")
  assert_acceptance_equal(
    [],
    candidate_obligation_page(obligation_id: @obligation_id).dig("data", "page", "items"),
    "Converged default-open page"
  )
end
