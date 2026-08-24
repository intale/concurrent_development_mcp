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
