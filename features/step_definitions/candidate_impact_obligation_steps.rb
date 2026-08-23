# frozen_string_literal: true

Given(
  "Rails 4 to Rails 5 Candidate pair {string} has registered attributed impact surfaces"
) do |prefix|
  prepare_candidate_obligation_coordination(prefix:)
  submit_candidate_obligation_pair
end

Given(
  "Rails 4 to Rails 5 Candidate checkpoints {string} exist without impact surfaces"
) do |prefix|
  prepare_candidate_obligation_coordination(prefix:)
end

When("the user activates {string} Candidate impact policy through guidance Tasks") do |level|
  activate_candidate_obligation_policy(level:)
end

When("the policy reaction is delivered twice") do
  drive_candidate_policy_source(redeliver: true)
end

When("the empty policy sweep is delivered twice") do
  drive_candidate_policy_source(redeliver: true)
  assert_acceptance_equal([], candidate_obligation_events, "Empty policy sweep obligations")
end

When("both Rails impact surfaces register after the policy with duplicate delivery") do
  submit_candidate_obligation_surface("source")
  drive_candidate_registration_source("source", redeliver: true)
  submit_candidate_obligation_surface("target")
  drive_candidate_registration_source("target", redeliver: true)
end

Then("no Candidate compatibility obligation is durable") do
  assert_acceptance_equal([], candidate_obligation_events, "Non-gating policy obligations")
end

Then("the available Candidate impact policy is {string} without a gate") do |level|
  project_candidate_obligation_policy
  content = candidate_obligation_impact_view
  page = content.dig("data", "page")
  policy = page.fetch("impact_policy")
  assert_acceptance_equal("ok", content.fetch("status"), "Candidate impact policy query")
  assert_acceptance_equal(level, policy.fetch("enforcement"), "Candidate impact policy level")
  assert_acceptance_equal(1, page.fetch("relationships").length, "Potential Rails relationship")
  assert_acceptance_equal([], content.fetch("next_actions"), "Non-gating next actions")
  if level == "advisory"
    assert_acceptance(
      content.fetch("warnings").any? { _1.include?("advisory") },
      "Advisory policy warning is missing"
    )
  else
    assert_acceptance_equal([], content.fetch("warnings"), "Disabled policy warnings")
  end
  obligations = candidate_obligation_page.dig("data", "page", "items")
  assert_acceptance_equal([], obligations, "Available non-gating obligation page")
  assert_acceptance(
    (content.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Candidate impact policy view must not expose freshness"
  )
end

Then("one exact open Rails obligation is durable under {string}") do |level|
  events = candidate_obligation_events
  assert_acceptance_equal(1, events.length, "Durable Candidate compatibility obligations")
  event = events.sole
  payload = candidate_obligation_payload
  source = @obligation_candidates.fetch("source")
  target = @obligation_candidates.fetch("target")
  assert_acceptance_equal("open", payload.status, "Obligation status")
  assert_acceptance_equal(level, payload.enforcement, "Obligation enforcement")
  assert_acceptance_equal(
    CandidateImpactObligationAcceptanceWorld::REQUIRED_EVIDENCE,
    payload.required_evidence,
    "Required evidence"
  )
  assert_acceptance_equal(
    source.dig(:arguments, :candidate_id),
    payload.source_candidate.candidate_id,
    "Obligation source Candidate"
  )
  assert_acceptance_equal(
    target.dig(:arguments, :candidate_id),
    payload.target_candidate.candidate_id,
    "Obligation target Candidate"
  )
  assert_acceptance_equal(
    [ "semantic_key_match" ],
    payload.reasons.map(&:kind),
    "Exact Rails impact reasons"
  )
  assert_acceptance_equal(
    [ [ "dependency:rubygems:rails" ] ],
    payload.reasons.map(&:matches),
    "Exact Rails impact matches"
  )
  assert_acceptance_equal(
    %w[CandidateSubmitted CandidateChangeManifestCaptured CandidateImpactSurfaceDerived CandidateImpactSurfaceRegistered],
    [
      payload.source_candidate.candidate_event.type,
      payload.source_candidate.manifest_event.type,
      payload.source_candidate.surface_event.type,
      payload.source_candidate.registration_event.type
    ],
    "Source evidence references"
  )
  assert_acceptance_equal(
    @obligation_policy.fetch(:head),
    payload.policy.head,
    "Exact policy head"
  )
  parent = candidate_obligation_pair_scan_events.find { _1.id == event.causation_id }
  assert_acceptance(parent, "Obligation immediate Saga parent is missing")
  assert_acceptance_equal(parent.correlation_id, event.correlation_id, "Obligation Saga correlation")
  assert_acceptance(
    !event.metadata.key?("correlation_id"),
    "Correlation must not be duplicated in event metadata"
  )
end

Then("the obligation query stays available and empty before projection") do
  project_candidate_obligation_policy
  impact = candidate_obligation_impact_view
  assert_acceptance_equal(
    "verification_obligations_list",
    impact.fetch("next_actions").sole.fetch("tool"),
    "Gating policy recovery action"
  )
  content = candidate_obligation_page
  page = content.dig("data", "page")
  assert_acceptance_equal("ok", content.fetch("status"), "Lagging obligation query")
  assert_acceptance_equal([], page.fetch("items"), "Lagging obligation items")
  assert_acceptance_equal(false, page.fetch("has_more"), "Lagging obligation continuation")
  assert_acceptance(
    (content.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Lagging obligation page must remain available"
  )
end

When("the obligation creation reaches the read side twice") do
  project_candidate_obligation(redeliver: true)
end

Then("the agent sees one exact open Rails obligation under {string}") do |level|
  content = candidate_obligation_page(enforcement: level, status: "open")
  page = content.dig("data", "page")
  item = page.fetch("items").sole
  assert_acceptance_equal("ok", content.fetch("status"), "Available obligation status")
  assert_acceptance_equal(@obligation_id, item.fetch("obligation_id"), "Available obligation ID")
  assert_acceptance_equal(level, item.fetch("enforcement"), "Available obligation enforcement")
  assert_acceptance_equal(
    CandidateImpactObligationAcceptanceWorld::REQUIRED_EVIDENCE,
    item.fetch("required_evidence"),
    "Available evidence requirements"
  )
  assert_acceptance_equal(
    @obligation_candidates.dig("source", :arguments, :candidate_id),
    item.dig("source_candidate", "candidate_id"),
    "Available source Candidate"
  )
  assert_acceptance_equal(
    @obligation_candidates.dig("target", :arguments, :candidate_id),
    item.dig("target_candidate", "candidate_id"),
    "Available target Candidate"
  )
  assert_acceptance_equal(
    "VerificationObligationCreated",
    item.dig("evidence", "event", "type"),
    "Available obligation event"
  )
  assert_acceptance(item.dig("evidence", "causation_id"), "Available obligation causation is missing")
  assert_acceptance(item.dig("evidence", "correlation_id"), "Available obligation correlation is missing")
  assert_acceptance(
    !item.dig("evidence", "metadata").key?("correlation_id"),
    "Available metadata must not duplicate correlation"
  )
  assert_acceptance_equal(false, page.fetch("has_more"), "Available obligation continuation")
  assert_acceptance_equal(nil, page.fetch("next_global_position"), "Available obligation cursor")
end
