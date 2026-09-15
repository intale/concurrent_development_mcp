# frozen_string_literal: true

Given("an open Rails verification obligation {string}") do |prefix|
  prepare_open_verification_obligation(prefix:)
end

Given("the obligation creation is available on the read side") do
  project_candidate_obligation(redeliver: true)
end

When(
  "agent {string} submits claim command {string} for {int} seconds"
) do |agent_id, command_id, duration|
  @current_claim_attempt = submit_verification_obligation_claim(
    agent_id:,
    command_id:,
    duration:
  )
end

Then("a checkpointed Task exists before any claim fact") do
  events = task_events(@current_claim_attempt.fetch(:task_id))
  assert_acceptance_equal(
    [ "CoordinationTaskSubmitted" ],
    events.map(&:type),
    "Claim Task checkpoint"
  )
  assert_acceptance_equal([], verification_obligation_claim_events, "Pre-execution claim facts")
  assert_acceptance_equal(
    [ "CommandRegistered" ],
    command_events(@current_claim_attempt.fetch(:command_id)).map(&:type),
    "Pre-execution command lifecycle"
  )
end

When("the claim Task executes") do
  execute_verification_obligation_claim(@current_claim_attempt)
end

When("the claim Task executes while the first claim is active") do
  execute_verification_obligation_claim(@current_claim_attempt)
end

When("the active claim expires") do
  expires_at = @last_successful_claim.dig(:claim_data, "expires_at")
  assert_acceptance(expires_at, "Active claim expiry is missing")
  eventually("Active verification claim to expire", timeout_seconds: 35) do
    now = Time.now.utc
    [ now >= Time.iso8601(expires_at), now.iso8601(6) ]
  end
end

Then(
  "the claim Task completes for {string} with fencing token {int}"
) do |agent_id, fencing_token|
  attempt = @current_claim_attempt
  data = attempt.dig(:content, "data")
  assert_acceptance_equal("completed", attempt.dig(:state, "result", "status"), "Claim Task status")
  assert_acceptance_equal(false, attempt.dig(:result, "isError"), "Claim Task error")
  assert_acceptance_equal("ok", attempt.dig(:content, "status"), "Claim command status")
  assert_acceptance_equal(@obligation_id, data.fetch("obligation_id"), "Claim obligation")
  assert_acceptance_equal(agent_id, data.fetch("claimant_id"), "Claimant")
  assert_acceptance_equal(fencing_token, data.fetch("fencing_token"), "Claim fence")
  assert_acceptance(
    Coordinator::Shared::Types::UUID_V7_PATTERN.match?(data.fetch("claim_id")),
    "Claim ID is not UUIDv7"
  )
  attempt[:claim_data] = data
  @last_successful_claim = attempt
end

Then("the durable claim carries exact Task tracing") do
  attempt = @last_successful_claim
  submitted, started, task_completed = task_events(attempt.fetch(:task_id))
  claim = verification_obligation_claim_events.sole
  command_terminal = command_terminal_event(attempt.fetch(:command_id))
  assert_acceptance_equal("CommandSucceeded", command_terminal&.type, "Claim command terminal")
  assert_acceptance_equal(started.id, claim.causation_id, "Claim immediate parent")
  assert_acceptance_equal(claim.id, command_terminal.causation_id, "Command terminal immediate parent")
  assert_acceptance_equal(command_terminal.id, task_completed.causation_id, "Task completion parent")
  assert_acceptance_equal(
    [ submitted.correlation_id ],
    [ submitted, started, claim, command_terminal, task_completed ].map(&:correlation_id).uniq,
    "Claim Task correlation"
  )
  assert_acceptance(!claim.metadata.key?("correlation_id"), "Claim metadata duplicates correlation")
end

Then("the claim result describes coordination without claiming work or verification") do
  content = @last_successful_claim.fetch(:content)
  assert_acceptance(
    content.fetch("summary").include?("temporary exclusive coordination"),
    "Claim summary does not describe temporary coordination"
  )
  forbidden = %w[authenticated work_started work_completed verified satisfied succeeded merge_safe]
  assert_acceptance_equal([], content.fetch("data").keys & forbidden, "Unsupported claim semantics")
end

When("the same claim command is submitted again") do
  original = @last_successful_claim
  response = call_tool("verification_obligation_claim", original.fetch(:arguments))
  @current_claim_attempt = {
    agent_id: original.fetch(:agent_id),
    command_id: original.fetch(:command_id),
    arguments: original.fetch(:arguments),
    task_id: response.dig("result", "taskId"),
    submitted_response: response,
    replay_of: original
  }
end

Then("replay returns the original claim without another claim fact") do
  replay = @current_claim_attempt
  original = replay.fetch(:replay_of)
  assert_acceptance_equal(original.fetch(:task_id), replay.fetch(:task_id), "Replayed Task identity")
  assert_acceptance_equal("completed", replay.dig(:state, "result", "status"), "Replay Task status")
  assert_acceptance_equal(false, replay.dig(:result, "isError"), "Replay Task error")
  assert_acceptance_equal(original.fetch(:content), replay.fetch(:content), "Replayed claim result")
  assert_acceptance_equal(1, verification_obligation_claim_events.length, "Replayed claim events")
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(replay.fetch(:command_id)).map(&:type),
    "Replayed command lifecycle"
  )
end

Then("the claim Task reports the active {string} claim as a conflict") do |claimant_id|
  attempt = @current_claim_attempt
  content = attempt.fetch(:content)
  assert_acceptance_equal("completed", attempt.dig(:state, "result", "status"), "Conflict Task status")
  assert_acceptance_equal(true, attempt.dig(:result, "isError"), "Conflict Task error")
  assert_acceptance_equal("conflict", content.fetch("status"), "Claim conflict status")
  assert_acceptance_equal(
    "verification_obligation_already_claimed",
    content.dig("data", "code"),
    "Claim conflict code"
  )
  assert_acceptance_equal(claimant_id, content.dig("data", "details", "claimant_id"), "Current claimant")
  assert_acceptance_equal(1, content.dig("data", "details", "fencing_token"), "Current fence")
  @last_denied_claim = attempt
end

Then("the denied command records rejection without another claim fact") do
  assert_acceptance_equal(1, verification_obligation_claim_events.length, "Claims after denial")
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@last_denied_claim.fetch(:command_id)).map(&:type),
    "Denied command lifecycle"
  )
end

When(
  "agents {string} and {string} claim concurrently"
) do |first_agent, second_agent|
  @concurrent_claim_attempts = [ first_agent, second_agent ].map do |agent_id|
    submit_verification_obligation_claim(
      agent_id:,
      command_id: "cmd-cuc-claim-race-#{agent_id}",
      duration: 300
    )
  end
  @concurrent_claim_attempts.map do |attempt|
    Thread.new { execute_task(attempt.fetch(:task_id)) }
  end.each(&:value)
  @concurrent_claim_attempts.each do |attempt|
    attempt[:state] = task_request("tasks/get", attempt.fetch(:task_id))
    attempt[:result] = attempt.dig(:state, "result", "result")
    attempt[:content] = attempt.dig(:result, "structuredContent")
  end
end

Then("exactly one Task wins token 1 and the other reports an active-claim conflict") do
  successes, conflicts = @concurrent_claim_attempts.partition do |attempt|
    attempt.dig(:result, "isError") == false
  end
  assert_acceptance_equal(1, successes.length, "Concurrent claim winners")
  assert_acceptance_equal(1, conflicts.length, "Concurrent claim conflicts")
  assert_acceptance_equal(1, successes.sole.dig(:content, "data", "fencing_token"), "Winning fence")
  assert_acceptance_equal(
    "verification_obligation_already_claimed",
    conflicts.sole.dig(:content, "data", "code"),
    "Concurrent conflict"
  )
  assert_acceptance_equal(1, verification_obligation_claim_events.length, "Concurrent claim facts")
  lifecycle_facts = @concurrent_claim_attempts.sum do |attempt|
    command_events(attempt.fetch(:command_id)).length
  end
  assert_acceptance_equal(4, lifecycle_facts, "Concurrent command lifecycle facts")
end

Then("both immutable claim facts retain their distinct fences") do
  events = verification_obligation_claim_events
  assert_acceptance_equal(2, events.length, "Reclaim event history")
  assert_acceptance_equal(
    [ [ "agent-blue", 1 ], [ "agent-green", 2 ] ],
    events.map { _1.data.values_at("claimant_id", "fencing_token") },
    "Reclaim fences"
  )
  assert_acceptance(events.map(&:id).uniq.length == 2, "Reclaim rewrote claim identity")
end

Then(
  "the available view still reports an open unclaimed obligation"
) do
  content, page = available_verification_obligation(claim_state: "unclaimed")
  item = page.fetch("items").sole
  assert_acceptance_equal("ok", content.fetch("status"), "Lagging claim view status")
  assert_acceptance(
    content.fetch("summary").include?("Latest available projected"),
    "Lagging claim view omits eventual-consistency language"
  )
  assert_acceptance_equal("open", item.fetch("status"), "Lagging obligation status")
  assert_acceptance_equal("unclaimed", item.fetch("claim_state"), "Lagging claim state")
  assert_acceptance_equal(nil, item.fetch("claim"), "Lagging claim")
  assert_acceptance(Time.iso8601(page.fetch("observed_at")), "Lagging observation time is invalid")
  assert_acceptance(
    (content.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Lagging claim view must not expose freshness gates"
  )
end

When("the claim reaches the read side twice") do
  project_verification_obligation_claims(redeliver: true)
end

Then("the available view reports the open active claim") do
  content, page = available_verification_obligation(claim_state: "active")
  item = page.fetch("items").sole
  claim = item.fetch("claim")
  assert_acceptance_equal("ok", content.fetch("status"), "Converged claim view status")
  assert_acceptance_equal("open", item.fetch("status"), "Converged obligation status")
  assert_acceptance_equal("active", item.fetch("claim_state"), "Converged claim state")
  assert_acceptance_equal("agent-blue", claim.fetch("claimant_id"), "Converged claimant")
  assert_acceptance_equal(1, claim.fetch("fencing_token"), "Converged fence")
  assert_acceptance_equal(
    verification_obligation_claim_events.sole.global_position,
    claim.dig("evidence", "global_position"),
    "Converged claim evidence"
  )
  assert_acceptance(Time.iso8601(page.fetch("observed_at")), "Converged observation time is invalid")
  assert_acceptance(
    (item.keys & %w[authenticated work_started verified satisfied succeeded merge_safe]).empty?,
    "Converged claim view overstates claim semantics"
  )
end
