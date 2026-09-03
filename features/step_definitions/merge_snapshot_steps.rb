# frozen_string_literal: true

When("the agent registers merge snapshot {string} with command {string}") do |snapshot_id, command_id|
  @merge_snapshot_arguments = {
    command_id:,
    actor: { kind: "agent", id: "integrator-1" },
    merge_snapshot_id: snapshot_id,
    repository_id: @candidate_arguments.fetch(:repository_id),
    target_branch: @candidate_arguments.fetch(:target_branch),
    target_base_commit_oid: @candidate_arguments.fetch(:base_commit_oid),
    ordered_candidates: [
      {
        candidate_id: @candidate_arguments.fetch(:candidate_id),
        head_commit_oid: @candidate_arguments.fetch(:head_commit_oid)
      }
    ],
    merge_commit_oid: "9" * 40,
    producer: { name: "git-merge", version: "2.47.0" },
    run_id: "run-cuc-merge-snapshot",
    produced_at: "2026-08-24T15:30:00.000001Z"
  }
  @merge_snapshot_task_id = call_tool(
    "merge_snapshot_register",
    @merge_snapshot_arguments
  ).dig("result", "taskId")
  assert_acceptance(@merge_snapshot_task_id, "merge_snapshot_register did not return a Task")
  execute_task(@merge_snapshot_task_id)
  @merge_snapshot_task_state = task_request("tasks/get", @merge_snapshot_task_id)
end

Then("the merge snapshot Task completes with exact attributed Candidate evidence") do
  result = @merge_snapshot_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @merge_snapshot_task_state.dig("result", "status"), "Task")
  assert_acceptance_equal(false, result.fetch("isError"), "Tool error")
  assert_acceptance_equal("attributed_unverified", content.dig("data", "evidence_status"), "Evidence")
  event = event_store.read(
    streams.merge_snapshot(@merge_snapshot_arguments.fetch(:merge_snapshot_id)),
    Coordinator::Write::EventQueries::MERGE_SNAPSHOT_REGISTRATION
  ).sole
  members = event.data.fetch("ordered_candidates")
  assert_acceptance_equal(
    [ @candidate_arguments.fetch(:candidate_id) ],
    members.map { _1.fetch("candidate_id") },
    "Ordered Candidates"
  )
  assert_acceptance_equal(
    [ @candidate_arguments.fetch(:head_commit_oid) ],
    members.map { _1.fetch("head_commit_oid") },
    "Ordered heads"
  )
end

Then(
  "merge snapshot {string} remains available as not observed before projection"
) do |snapshot_id|
  payload = call_tool("merge_snapshot_get", { merge_snapshot_id: snapshot_id }).dig(
    "result", "structuredContent"
  )
  assert_acceptance_equal("not_found", payload.fetch("status"), "Lagging snapshot query")
  assert_acceptance(
    payload.fetch("warnings").any? { _1.include?("projection") },
    "Lag warning is missing"
  )
end

When("merge snapshot {string} reaches the read side") do |snapshot_id|
  await_read_model("Merge snapshot #{snapshot_id} to become available") do
    payload = call_tool("merge_snapshot_get", { merge_snapshot_id: snapshot_id })
      .dig("result", "structuredContent")
    [ payload.dig("data", "snapshot", "merge_snapshot_id") == snapshot_id, payload ]
  end
end

Then("merge snapshot {string} is available without a freshness gate") do |snapshot_id|
  payload = call_tool("merge_snapshot_get", { merge_snapshot_id: snapshot_id }).dig(
    "result", "structuredContent"
  )
  snapshot = payload.dig("data", "snapshot")
  assert_acceptance_equal("ok", payload.fetch("status"), "Snapshot query")
  assert_acceptance_equal(snapshot_id, snapshot.fetch("merge_snapshot_id"), "Snapshot identity")
  assert_acceptance_equal("attributed_unverified", snapshot.fetch("evidence_status"), "Evidence")
  assert_acceptance(
    (snapshot.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Merge snapshot must not expose a freshness gate"
  )
end

When("the agent submits {string} merge verification with command {string}") do |conclusion, command_id|
  @merge_verification_arguments = merge_verification_arguments(
    command_id:,
    conclusion:
  )
  submit_merge_verification(@merge_verification_arguments)
end

When(
  "the agent submits merge verification with a stale digest as command {string}"
) do |command_id|
  arguments = merge_verification_arguments(command_id:, conclusion: "passed")
  @merge_verification_arguments = arguments.merge(
    binding: arguments.fetch(:binding).merge(snapshot_digest: "sha256:#{'f' * 64}")
  )
  submit_merge_verification(@merge_verification_arguments)
end

Then("the merge verification Task completes with status {string}") do |status|
  assert_acceptance_equal("completed", @merge_verification_state.dig("result", "status"), "Task")
  result = @merge_verification_state.dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Verification error")
  assert_acceptance_equal(
    status,
    result.dig("structuredContent", "data", "status"),
    "Verification status"
  )
end

Then(
  "{int} submitted report(s) and {int} verified fact(s) are durable for the exact snapshot"
) do |submission_count, verified_count|
  events = merge_verification_events
  assert_acceptance_equal(
    submission_count,
    events.count { _1.type == "MergeSnapshotVerificationSubmitted" },
    "Submitted verification facts"
  )
  assert_acceptance_equal(
    verified_count,
    events.count { _1.type == "MergeSnapshotVerified" },
    "Verified snapshot facts"
  )
  assert_acceptance_equal(
    [ @merge_snapshot_arguments.fetch(:merge_snapshot_id) ],
    events.map { _1.data.fetch("merge_snapshot_id") }.uniq,
    "Verification snapshot binding"
  )
end

Then("the available merge snapshot still reports {string}") do |status|
  assert_merge_snapshot_verification_status(status)
end

When("the submitted merge verification reaches the read side twice") do
  await_read_model("Merge snapshot verification report to become available") do
    snapshot = merge_snapshot_payload
    submissions = snapshot.dig("verification", "submissions") || []
    [ submissions.any?, snapshot ]
  end
end

Then(
  "the available merge snapshot reports {string} with one attributed report"
) do |status|
  snapshot = merge_snapshot_payload
  verification = snapshot.fetch("verification")
  assert_acceptance_equal(status, verification.fetch("status"), "Verification status")
  assert_acceptance_equal(1, verification.fetch("submissions").length, "Observed reports")
  source = verification.fetch("submissions").sole.fetch("source")
  assert_acceptance_equal("agent", source.dig("actor", "kind"), "Report attribution")
end

When("the terminal merge verification reaches the read side after a subscription restart") do
  restart_read_model_subscriptions if @live_subscription_sets&.key?(:read_models)
  await_read_model("Merge snapshot verification to become terminal") do
    snapshot = merge_snapshot_payload
    [ snapshot.dig("verification", "status") == "verified", snapshot ]
  end
end

Then(
  "the available merge snapshot reports {string} without a freshness gate"
) do |status|
  snapshot = merge_snapshot_payload
  verification = snapshot.fetch("verification")
  assert_acceptance_equal(status, verification.fetch("status"), "Verification status")
  assert_acceptance(verification.fetch("verified"), "Verified decision is missing")
  assert_acceptance(
    (verification.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Merge verification must not expose a freshness gate"
  )
end

Then(
  "the merge verification Task reports {string} without verification facts"
) do |code|
  assert_acceptance_equal("completed", @merge_verification_state.dig("result", "status"), "Task")
  result = @merge_verification_state.dig("result", "result")
  assert_acceptance_equal(true, result.fetch("isError"), "Denied verification")
  assert_acceptance_equal(code, result.dig("structuredContent", "data", "code"), "Denial code")
  assert_acceptance_equal([], merge_verification_events, "Denied verification facts")
  assert_acceptance_equal(
    %w[CommandRegistered CommandRejected],
    command_events(@merge_verification_arguments.fetch(:command_id)).map(&:type),
    "Denied verification command lifecycle"
  )
end

When("the agent requests merge authorization with command {string}") do |command_id|
  submit_merge_authorization(merge_authorization_arguments(command_id:))
end

When("the merge snapshot Candidates complete their WorkItems") do
  candidates =
    if @obligation_candidates
      @obligation_candidates.values
    else
      [ { arguments: @candidate_arguments, coordination: @candidate_coordination } ]
    end
  candidates.each do |candidate|
    complete_merge_candidate_work_item(candidate)
  end
end

When("the integrator registers exact Rails pair snapshot {string}") do |snapshot_id|
  candidates = %w[source target].map do |role|
    candidate = @obligation_candidates.fetch(role).fetch(:arguments)
    {
      candidate_id: candidate.fetch(:candidate_id),
      head_commit_oid: candidate.fetch(:head_commit_oid)
    }
  end
  source = @obligation_candidates.fetch("source").fetch(:arguments)
  @merge_snapshot_arguments = {
    command_id: "cmd-cuc-merge-auth-open-snapshot",
    actor: { kind: "agent", id: "integrator-1" },
    merge_snapshot_id: snapshot_id,
    repository_id: source.fetch(:repository_id),
    target_branch: source.fetch(:target_branch),
    target_base_commit_oid: source.fetch(:base_commit_oid),
    ordered_candidates: candidates,
    merge_commit_oid: "8" * 40,
    producer: { name: "git-merge", version: "2.47.0" },
    run_id: "run-cuc-merge-auth-open",
    produced_at: "2026-08-24T15:30:00.000001Z"
  }
  @merge_snapshot_task_id = call_tool(
    "merge_snapshot_register",
    @merge_snapshot_arguments
  ).dig("result", "taskId")
  assert_acceptance(@merge_snapshot_task_id, "merge_snapshot_register did not return a Task")
  execute_task(@merge_snapshot_task_id)
  @merge_snapshot_task_state = task_request("tasks/get", @merge_snapshot_task_id)
end

When(
  "the agent requests merge authorization against a changed target base with command {string}"
) do |command_id|
  arguments = merge_authorization_arguments(command_id:)
  submit_merge_authorization(
    arguments.merge(
      target_base_observation: arguments.fetch(:target_base_observation).merge(
        commit_oid: "c" * 40
      )
    )
  )
end

Then("the merge authorization Task completes with durable outcome {string}") do |outcome|
  assert_acceptance_equal("completed", @merge_authorization_state.dig("result", "status"), "Task")
  result = @merge_authorization_state.dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Authorization decision")
  assert_acceptance_equal(
    outcome,
    result.dig("structuredContent", "data", "outcome"),
    "Authorization outcome"
  )
  assert_acceptance_equal(1, merge_authorization_events.length, "Authorization decisions")
  assert_acceptance_equal(
    %w[CommandRegistered CommandSucceeded],
    command_events(@merge_authorization_arguments.fetch(:command_id)).map(&:type),
    "Command lifecycle"
  )
end

Then("the authorization explains {string}") do |code|
  reasons = @merge_authorization_state.dig(
    "result", "result", "structuredContent", "data", "reasons"
  )
  assert_acceptance(reasons.any? { _1.fetch("code") == code }, "Missing authorization reason #{code}")
end

Then("the available merge snapshot has no observed authorization yet") do
  snapshot = merge_snapshot_payload
  assert_acceptance_equal(nil, snapshot.fetch("latest_authorization"), "Lagging authorization")
end

When("the merge authorization reaches the read side after a subscription restart") do
  expected = {
    "MergeAuthorizationGranted" => "granted",
    "MergeAuthorizationDenied" => "denied"
  }[merge_authorization_events.sole.type]
  assert_acceptance(expected, "Merge authorization outcome type is unsupported")
  restart_read_model_subscriptions if @live_subscription_sets&.key?(:read_models)
  await_read_model("Merge authorization #{expected} to become available") do
    snapshot = merge_snapshot_payload
    [ snapshot.dig("latest_authorization", "outcome") == expected, snapshot ]
  end
end

Then(
  "the available merge snapshot reports authorization {string} without a freshness gate"
) do |outcome|
  authorization = merge_snapshot_payload.fetch("latest_authorization")
  assert_acceptance_equal(outcome, authorization.fetch("outcome"), "Authorization outcome")
  assert_acceptance(
    (authorization.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Merge authorization must not expose a freshness gate"
  )
end

When("the agent records the exact external merge with command {string}") do |command_id|
  authorization = @merge_authorization_state.dig(
    "result", "result", "structuredContent", "data"
  )
  @merge_observation_arguments = {
    command_id:,
    actor: { kind: "agent", id: "integrator-1" },
    merge_snapshot_id: @merge_snapshot_arguments.fetch(:merge_snapshot_id),
    authorization_event: authorization.fetch("decision_event"),
    authorization_decision_digest: authorization.fetch("decision_digest"),
    repository_id: @merge_snapshot_arguments.fetch(:repository_id),
    target_branch: @merge_snapshot_arguments.fetch(:target_branch),
    object_format: "sha1",
    target_before_commit_oid: @merge_snapshot_arguments.fetch(:target_base_commit_oid),
    target_after_commit_oid: @merge_snapshot_arguments.fetch(:merge_commit_oid),
    observer: { name: "git-provider-webhook", version: "2026-08" },
    run_id: "run-#{command_id}",
    observed_at: "2026-08-24T17:30:00.000001Z"
  }
  response = call_tool("merge_observation_record", @merge_observation_arguments)
  @merge_observation_task_id = response.dig("result", "taskId")
  assert_acceptance(@merge_observation_task_id, "merge_observation_record did not return a Task")
  execute_task(@merge_observation_task_id)
  @merge_observation_state = task_request("tasks/get", @merge_observation_task_id)
end

Then("the merge observation Task completes with attributed unverified evidence") do
  assert_acceptance_equal("completed", @merge_observation_state.dig("result", "status"), "Task")
  result = @merge_observation_state.dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Merge observation")
  assert_acceptance_equal(
    "attributed_unverified",
    result.dig("structuredContent", "data", "evidence_status"),
    "Observation evidence"
  )
  assert_acceptance_equal(1, merge_observation_events.length, "Merge observations")
end

Then("the available merge snapshot has no observed merge yet") do
  assert_acceptance_equal(nil, merge_snapshot_payload.fetch("observation"), "Lagging observation")
end

When("the merge observation reaches the read side after a subscription restart") do
  restart_read_model_subscriptions if @live_subscription_sets&.key?(:read_models)
  await_read_model("Merge observation to become available") do
    snapshot = merge_snapshot_payload
    [ !snapshot["observation"].nil?, snapshot ]
  end
end

Then("the available merge snapshot reports the exact merge without a freshness gate") do
  observation = merge_snapshot_payload.fetch("observation")
  assert_acceptance_equal(
    @merge_snapshot_arguments.fetch(:merge_commit_oid),
    observation.fetch("target_after_commit_oid"),
    "Observed merge OID"
  )
  assert_acceptance_equal("attributed_unverified", observation.fetch("evidence_status"), "Evidence")
  assert_acceptance(
    (observation.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Merge observation must not expose a freshness gate"
  )
end

def merge_verification_arguments(command_id:, conclusion:)
  receipt = @merge_snapshot_task_state.dig("result", "result", "structuredContent", "data")
  findings = if conclusion == "passed"
               []
  else
               [
                 {
                   code: "cucumber-#{conclusion}",
                   severity: conclusion == "failed" ? "error" : "warning",
                   summary: "The external combined-test report concluded #{conclusion}."
                 }
               ]
  end
  {
    command_id:,
    actor: { kind: "agent", id: "verifier-1" },
    merge_snapshot_id: @merge_snapshot_arguments.fetch(:merge_snapshot_id),
    binding: {
      snapshot_event: receipt.fetch("snapshot_event"),
      snapshot_digest: receipt.fetch("snapshot_digest"),
      repository_id: @merge_snapshot_arguments.fetch(:repository_id),
      target_branch: @merge_snapshot_arguments.fetch(:target_branch),
      object_format: "sha1",
      target_base_commit_oid: @merge_snapshot_arguments.fetch(:target_base_commit_oid),
      ordered_candidates: @merge_snapshot_arguments.fetch(:ordered_candidates),
      merge_commit_oid: @merge_snapshot_arguments.fetch(:merge_commit_oid)
    },
    assessment: {
      evidence_kind: "combined_tests",
      producer: { name: "cucumber-external-verifier", version: "1.0.0" },
      run_id: "run-#{command_id}",
      test_suite_digest: Coordinator::Shared::CanonicalJson.new.sha256([ command_id, "suite" ]),
      environment_digest: Coordinator::Shared::CanonicalJson.new.sha256([ command_id, "environment" ]),
      result_digest: Coordinator::Shared::CanonicalJson.new.sha256([ command_id, conclusion ]),
      conclusion:,
      findings:,
      produced_at: "2026-08-24T16:30:00.000001Z"
    }
  }
end

def merge_authorization_arguments(command_id:)
  registration = @merge_snapshot_task_state.dig("result", "result", "structuredContent", "data")
  verified_event = merge_verification_events.find { _1.type == "MergeSnapshotVerified" }
  assert_acceptance(verified_event, "Exact merge verification is missing")
  {
    command_id:,
    actor: { kind: "agent", id: "integrator-1" },
    merge_snapshot_id: @merge_snapshot_arguments.fetch(:merge_snapshot_id),
    snapshot_binding: {
      registration_event: registration.fetch("snapshot_event"),
      snapshot_digest: registration.fetch("snapshot_digest"),
      verification_event: merge_event_reference(verified_event),
      verification_digest: verified_event.data.fetch("verification_digest")
    },
    target_base_observation: {
      repository_id: @merge_snapshot_arguments.fetch(:repository_id),
      target_branch: @merge_snapshot_arguments.fetch(:target_branch),
      object_format: "sha1",
      commit_oid: @merge_snapshot_arguments.fetch(:target_base_commit_oid),
      observer: { name: "git-fetch", version: "2.47.0" },
      run_id: "base-#{command_id}",
      observed_at: "2026-08-24T16:45:00.000001Z"
    },
    expected_impact_policy: merge_authorization_expected_policy
  }
end

def merge_authorization_expected_policy
  return unless @obligation_policy

  {
    partition_event: candidate_obligation_event_reference(
      @obligation_policy.fetch(:partition_event)
    ).to_h,
    head: @obligation_policy.fetch(:head).to_h,
    definition_digest: @obligation_policy.fetch(:decision_event).data.fetch("definition_digest")
  }
end

def submit_merge_authorization(arguments)
  @merge_authorization_arguments = arguments
  response = call_tool("merge_authorization_request", arguments)
  @merge_authorization_task_id = response.dig("result", "taskId")
  assert_acceptance(@merge_authorization_task_id, "merge_authorization_request did not return a Task")
  execute_task(@merge_authorization_task_id)
  @merge_authorization_state = task_request("tasks/get", @merge_authorization_task_id)
end

def submit_merge_verification(arguments)
  response = call_tool("merge_verification_submit", arguments)
  @merge_verification_task_id = response.dig("result", "taskId")
  assert_acceptance(@merge_verification_task_id, "merge_verification_submit did not return a Task")
  execute_task(@merge_verification_task_id)
  @merge_verification_state = task_request("tasks/get", @merge_verification_task_id)
end

def complete_merge_candidate_work_item(candidate)
  arguments = candidate.fetch(:arguments)
  coordination = candidate.fetch(:coordination)
  reservation = coordination.fetch(:reservation)
  suffix = arguments.fetch(:candidate_id).downcase
  release_task_id = submit_and_execute(
    "lease_release",
    command_id: "cmd-cuc-merge-release-#{suffix}",
    actor: arguments.fetch(:actor),
    change_set_id: arguments.fetch(:change_set_id),
    work_item_id: arguments.fetch(:work_item_id),
    attempt_id: arguments.fetch(:attempt_id),
    lease_set_id: reservation.fetch("lease_set_id"),
    leases: reservation.fetch("resources").map do |reference|
      {
        resource_id: reference.fetch("resource_id"),
        lease_id: reference.fetch("lease_id"),
        fencing_token: reference.fetch("fencing_token")
      }
    end
  )
  assert_successful_task(release_task_id, "Merge Candidate write-set release")
  completion_task_id = submit_and_execute(
    "work_item_complete",
    command_id: "cmd-cuc-merge-complete-#{suffix}",
    actor: arguments.fetch(:actor),
    change_set_id: arguments.fetch(:change_set_id),
    work_item_id: arguments.fetch(:work_item_id),
    attempt_id: arguments.fetch(:attempt_id),
    candidate_id: arguments.fetch(:candidate_id),
    produced_outputs: []
  )
  assert_successful_task(completion_task_id, "Merge Candidate WorkItem completion")
end

def merge_verification_events
  event_store.read(
    streams.merge_snapshot(@merge_snapshot_arguments.fetch(:merge_snapshot_id)),
    Coordinator::Write::EventReadCriteria.new(
      event_types: %w[MergeSnapshotVerificationSubmitted MergeSnapshotVerified],
      maximum_count: 34,
      direction: :asc
    )
  )
end

def merge_authorization_events
  authorization_id = @merge_authorization_state.dig(
    "result", "result", "structuredContent", "data", "authorization_id"
  )
  event_store.read(
    streams.merge_authorization(authorization_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: %w[MergeAuthorizationGranted MergeAuthorizationDenied],
      maximum_count: 1,
      direction: :asc
    )
  )
end

def merge_observation_events
  event_store.read(
    streams.merge_snapshot(@merge_observation_arguments.fetch(:merge_snapshot_id)),
    Coordinator::Write::EventQueries::MERGE_OBSERVATION
  )
end

def merge_event_reference(event)
  {
    event_id: event.id,
    type: event.type,
    stream_context: event.stream.context,
    stream_name: event.stream.stream_name,
    stream_id: event.stream.stream_id,
    stream_revision: event.stream_revision
  }
end

def merge_snapshot_payload
  call_tool(
    "merge_snapshot_get",
    { merge_snapshot_id: @merge_snapshot_arguments.fetch(:merge_snapshot_id) }
  ).dig("result", "structuredContent", "data", "snapshot")
end

def assert_merge_snapshot_verification_status(status)
  snapshot = merge_snapshot_payload
  assert_acceptance_equal(status, snapshot.dig("verification", "status"), "Verification status")
end
