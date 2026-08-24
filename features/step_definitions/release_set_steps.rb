# frozen_string_literal: true

Given("ReleaseSet {string} has two exact current repository grants for one ChangeSet") do |prefix|
  @release_set_arguments = ReleaseSetScenario.prepare_input(prefix: "cuc-#{prefix.downcase}")
end

When("the agent prepares the ordered ReleaseSet through MCP") do
  @release_set_task_id = call_tool(
    "release_set_prepare",
    @release_set_arguments
  ).dig("result", "taskId")
  assert_acceptance(@release_set_task_id, "release_set_prepare did not return a Task")
  execute_task(@release_set_task_id)
  @release_set_task_state = task_request("tasks/get", @release_set_task_id)
end

Then("the ReleaseSet Task completes with the exact repository order") do
  result = @release_set_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @release_set_task_state.dig("result", "status"), "Task")
  assert_acceptance_equal(false, result.fetch("isError"), "ReleaseSet error")
  assert_acceptance_equal("ok", content.fetch("status"), "ReleaseSet result")
  assert_acceptance_equal(
    %w[billing ledger],
    content.dig("data", "ordered_members").map { _1.fetch("repository_id") },
    "Repository order"
  )
end

Then("one prepared fact and command completion preserve the Task trace") do
  prepared = release_set_events(@release_set_arguments.fetch(:release_set_id)).sole
  completion = command_events(@release_set_arguments.fetch(:command_id)).sole
  started = task_events(@release_set_task_id).find do |event|
    event.type == "CoordinationTaskExecutionStarted"
  end
  assert_acceptance(started, "ReleaseSet Task has no execution-started fact")
  assert_acceptance_equal(started.id, prepared.causation_id, "Preparation causation")
  assert_acceptance_equal(started.id, completion.causation_id, "Completion causation")
  assert_acceptance_equal(
    [ started.correlation_id ],
    [ prepared, completion ].map(&:correlation_id).uniq,
    "Preparation correlation"
  )
end

Then("the ReleaseSet remains available as not observed before projection") do
  content = release_set_view(@release_set_arguments.fetch(:release_set_id))
  assert_acceptance_equal("not_found", content.fetch("status"), "Lagging ReleaseSet")
  assert_acceptance(
    (content.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Lagging ReleaseSet must not expose a freshness gate"
  )
end

When("the ReleaseSet preparation reaches the read side twice") do
  event = release_set_events(@release_set_arguments.fetch(:release_set_id)).sole
  2.times { Coordinator::Container["projectors.release_sets_v1"].call(event) }
end

Then("the ordered ReleaseSet is available without a freshness gate") do
  content = release_set_view(@release_set_arguments.fetch(:release_set_id))
  release_set = content.dig("data", "release_set")
  assert_acceptance_equal("ok", content.fetch("status"), "ReleaseSet view")
  assert_acceptance_equal(
    %w[billing ledger],
    release_set.fetch("ordered_members").map { _1.fetch("repository_id") },
    "Projected repository order"
  )
  assert_acceptance_equal("prepared", release_set.fetch("status"), "Projected status")
  assert_acceptance(
    (release_set.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "ReleaseSet view must not expose a freshness gate"
  )
end

When("the agent records both repository integrations through MCP in order") do
  release_set_id = @release_set_arguments.fetch(:release_set_id)
  prepared = release_set_payload(release_set_lifecycle_events(release_set_id).first)
  @release_integration_tasks = prepared.ordered_members.map.with_index do |member, index|
    observation_task_id = submit_and_execute(
      "merge_observation_record",
      command_id: "cmd-cuc-release-observe-#{index + 1}",
      actor: { kind: "agent", id: "release-integrator-1" },
      merge_snapshot_id: member.merge_snapshot_id,
      authorization_event: member.authorization_event.to_h,
      authorization_decision_digest: member.authorization_decision_digest,
      repository_id: member.repository_id,
      target_branch: member.target_branch,
      object_format: member.object_format,
      target_before_commit_oid: member.target_base_commit_oid,
      target_after_commit_oid: member.merge_commit_oid,
      observer: { name: "release-adapter", version: "1.0.0" },
      run_id: "cuc-release-observation-#{index + 1}",
      observed_at: "2026-08-24T21:00:0#{index}.000000Z"
    )
    observation = event_store.read(
      streams.merge_snapshot(member.merge_snapshot_id),
      Coordinator::Write::EventQueries::MERGE_OBSERVATION
    ).sole
    observation_payload = release_set_payload(observation)
    task_id = submit_and_execute(
      "release_repository_integration_record",
      command_id: "cmd-cuc-release-integrate-#{index + 1}",
      actor: { kind: "agent", id: "release-integrator-1" },
      release_set_id:,
      repository_id: member.repository_id,
      attempt_id: "cuc-release-attempt-#{index + 1}",
      outcome: "integrated",
      merge_observation_event: release_event_reference(observation).to_h,
      observation_digest: observation_payload.observation_digest,
      failure: nil
    )
    { observation_task_id:, task_id: }
  end
end

When("the agent records passing composite verification through MCP") do
  release_set_id = @release_set_arguments.fetch(:release_set_id)
  integrations = release_set_lifecycle_events(release_set_id).select do |event|
    event.type == "RepositoryIntegrationRecorded"
  end
  @release_verification_task_id = submit_and_execute(
    "release_verification_record",
    command_id: "cmd-cuc-release-verification",
    actor: { kind: "agent", id: "release-verifier-1" },
    release_set_id:,
    integration_events: integrations.map { release_event_reference(_1).to_h },
    evidence: {
      producer: { name: "release-suite", version: "1.0.0" },
      run_id: "cuc-release-verification-run",
      environment_digest: "sha256:#{'e' * 64}",
      result_digest: "sha256:#{'f' * 64}",
      outcome: "passed",
      findings: [],
      produced_at: "2026-08-24T21:30:00.000000Z"
    }
  )
end

Then("the integration and verification Tasks preserve one ReleaseSet trace") do
  release_set_id = @release_set_arguments.fetch(:release_set_id)
  lifecycle = release_set_lifecycle_events(release_set_id)
  expected_correlation = lifecycle.first.correlation_id
  assert_acceptance_equal(
    [ expected_correlation ],
    lifecycle.map(&:correlation_id).uniq,
    "ReleaseSet lifecycle correlation"
  )
  domain_tasks = @release_integration_tasks.map { _1.fetch(:task_id) } + [ @release_verification_task_id ]
  domain_events = lifecycle.drop(1)
  domain_tasks.zip(domain_events).each do |task_id, event|
    started = task_events(task_id).find { _1.type == "CoordinationTaskExecutionStarted" }
    assert_acceptance_equal(started.id, event.causation_id, "ReleaseSet lifecycle causation")
    state = task_request("tasks/get", task_id)
    assert_acceptance_equal("completed", state.dig("result", "status"), "ReleaseSet Task")
  end
end

Then("the older ReleaseSet view remains available while lifecycle projection lags") do
  prepared = release_set_lifecycle_events(@release_set_arguments.fetch(:release_set_id)).first
  Coordinator::Container["projectors.release_sets_v1"].call(prepared)
  release_set = release_set_view(@release_set_arguments.fetch(:release_set_id)).dig("data", "release_set")
  assert_acceptance_equal("prepared", release_set.fetch("status"), "Lagging ReleaseSet status")
  assert_acceptance_equal([], release_set.fetch("integrations"), "Lagging integrations")
end

When("the complete ReleaseSet lifecycle reaches the read side twice") do
  projector = Coordinator::Container["projectors.release_sets_v1"]
  release_set_lifecycle_events(@release_set_arguments.fetch(:release_set_id)).each do |event|
    2.times { projector.call(event) }
  end
end

Then("the verified ReleaseSet is available with exact ordered evidence") do
  release_set = release_set_view(@release_set_arguments.fetch(:release_set_id)).dig("data", "release_set")
  assert_acceptance_equal("verified", release_set.fetch("status"), "Verified ReleaseSet status")
  assert_acceptance_equal("passed", release_set.fetch("verification_status"), "Verification status")
  assert_acceptance_equal(
    %w[billing ledger],
    release_set.fetch("integrations").map { _1.fetch("repository_id") },
    "Integration order"
  )
  assert_acceptance_equal(1, release_set.fetch("verifications").length, "Verification history")
end
