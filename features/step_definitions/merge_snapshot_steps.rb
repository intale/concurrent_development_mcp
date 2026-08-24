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
  event = event_store.read(
    streams.merge_snapshot(snapshot_id),
    Coordinator::Write::EventQueries::MERGE_SNAPSHOT_REGISTRATION
  ).sole
  Coordinator::Container["projectors.merge_snapshots_v1"].call(event)
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
  event = merge_verification_events.find do |candidate|
    candidate.type == "MergeSnapshotVerificationSubmitted"
  end
  2.times { Coordinator::Container["projectors.merge_snapshots_v1"].call(event) }
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

When("the terminal merge verification reaches the read side twice") do
  event = merge_verification_events.find { _1.type == "MergeSnapshotVerified" }
  2.times { Coordinator::Container["projectors.merge_snapshots_v1"].call(event) }
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
    [],
    command_events(@merge_verification_arguments.fetch(:command_id)),
    "Denied verification receipt"
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

def submit_merge_verification(arguments)
  response = call_tool("merge_verification_submit", arguments)
  @merge_verification_task_id = response.dig("result", "taskId")
  assert_acceptance(@merge_verification_task_id, "merge_verification_submit did not return a Task")
  execute_task(@merge_verification_task_id)
  @merge_verification_state = task_request("tasks/get", @merge_verification_task_id)
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
