# frozen_string_literal: true

When("user {string} submits waiver command {string}") do |user_id, command_id|
  submit_verification_obligation_waiver(user_id:, command_id:)
end

Then("the waiver Task is durable before any waiver fact") do
  assert_acceptance_equal(
    [ "CoordinationTaskSubmitted" ],
    task_events(@waiver_attempt.fetch(:task_id)).map(&:type),
    "Waiver Task checkpoint"
  )
  assert_acceptance_equal(
    [],
    verification_obligation_lifecycle_events.select { _1.type == "VerificationObligationWaived" },
    "Pre-execution waiver facts"
  )
end

When("the waiver Task executes") do
  execute_verification_obligation_waiver
end

Then("the waiver Task completes with an attributed coordination override") do
  data = @waiver_attempt.dig(:content, "data")
  assert_acceptance_equal("completed", @waiver_attempt.dig(:state, "result", "status"), "Waiver Task")
  assert_acceptance_equal(false, @waiver_attempt.dig(:result, "isError"), "Waiver error")
  assert_acceptance_equal("waived", data.fetch("status"), "Waiver status")
  assert_acceptance_equal("accepted_risk", data.dig("reason", "code"), "Waiver reason")
  forbidden = %w[authenticated verified satisfied succeeded merge_safe]
  assert_acceptance_equal([], data.keys & forbidden, "Unsupported waiver semantics")
end

Then("the available obligation still reports open before waiver projection") do
  content = candidate_obligation_page(status: "open")
  assert_acceptance_equal("open", content.dig("data", "page", "items").sole.fetch("status"), "Lagging waiver view")
  assert_acceptance(
    (content.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Waiver lag must not introduce a freshness gate"
  )
end

When("the obligation lifecycle reaches the read side after a subscription restart") do
  project_verification_obligation_lifecycle
end

Then("the available obligation reports waived with the exact attributed reason") do
  item = candidate_obligation_page(status: "waived").dig("data", "page", "items").sole
  assert_acceptance_equal("waived", item.fetch("status"), "Projected waiver status")
  assert_acceptance_equal("accepted_risk", item.dig("outcome", "reason", "code"), "Projected waiver reason")
  assert_acceptance_equal("user", item.dig("outcome", "evidence", "actor", "kind"), "Projected waiver actor")
end

When("the user corrects the Candidate impact policy through guidance Tasks") do
  correct_candidate_obligation_policy
end

When("the validity policy reaction is observed across a process restart") do
  drive_verification_obligation_validity(redeliver: true)
end

Then("one policy invalidation is durable with exact Saga tracing") do
  invalidations = verification_obligation_lifecycle_events.select do
    _1.type == "VerificationObligationInvalidated"
  end
  invalidation = invalidations.sole
  started = verification_obligation_validity_scan_events.find do
    _1.type == "VerificationObligationValidityScanStarted"
  end
  assert_acceptance_equal(started.id, invalidation.causation_id, "Invalidation immediate parent")
  assert_acceptance_equal(
    @corrected_partition_event.correlation_id,
    invalidation.correlation_id,
    "Invalidation Saga correlation"
  )
end

Then("the available obligation still reports open before invalidation projection") do
  content = candidate_obligation_page(status: "open")
  assert_acceptance_equal("open", content.dig("data", "page", "items").sole.fetch("status"), "Lagging invalidation view")
end

Then("the available obligation reports invalidated by the exact later partition") do
  item = candidate_obligation_page(status: "invalidated").dig("data", "page", "items").sole
  assert_acceptance_equal("invalidated", item.fetch("status"), "Projected invalidation status")
  assert_acceptance_equal(
    @corrected_partition_event.id,
    item.dig("outcome", "superseding_partition_event", "event_id"),
    "Projected superseding partition"
  )
end
