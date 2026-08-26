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
    expected_release_repository_ids,
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
    expected_release_repository_ids,
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
    expected_release_repository_ids,
    release_set.fetch("integrations").map { _1.fetch("repository_id") },
    "Integration order"
  )
  assert_acceptance_equal(1, release_set.fetch("verifications").length, "Verification history")
end

When("the agent records external ReleaseSet activation through MCP") do
  release_set_id = @release_set_arguments.fetch(:release_set_id)
  verification = release_set_lifecycle_events(release_set_id).find do |event|
    event.type == "ReleaseSetVerificationRecorded"
  end
  payload = release_set_payload(verification)
  @release_activation_task_id = submit_and_execute(
    "release_activation_record",
    command_id: "cmd-cuc-release-activation",
    actor: { kind: "agent", id: "release-operator-1" },
    release_set_id:,
    verification_event: release_event_reference(verification).to_h,
    verification_digest: payload.verification_digest,
    activation_point: {
      kind: "deployment_manifest",
      environment: "production",
      external_reference: "deployments/cuc-release-activation",
      state_digest: "sha256:#{'a' * 64}",
      producer: { name: "deployment-controller", version: "1.0.0" },
      run_id: "cuc-release-activation-run",
      activated_at: "2026-08-24T22:00:00.000000Z"
    }
  )
end

When("the ReleaseSet lifecycle Saga processes activation twice") do
  activation = release_set_lifecycle_events(
    @release_set_arguments.fetch(:release_set_id)
  ).find { _1.type == "ReleaseSetActivated" }
  2.times { Coordinator::Container["process_managers.release_set_lifecycle"].call(activation) }
end

Then("the activation Task and Saga completion preserve the ReleaseSet trace") do
  lifecycle = release_set_lifecycle_events(@release_set_arguments.fetch(:release_set_id))
  activation = lifecycle.find { _1.type == "ReleaseSetActivated" }
  completion = lifecycle.select { _1.type == "ReleaseSetCompleted" }.sole
  started = task_events(@release_activation_task_id).find do |event|
    event.type == "CoordinationTaskExecutionStarted"
  end
  state = task_request("tasks/get", @release_activation_task_id)
  assert_acceptance_equal("completed", state.dig("result", "status"), "Activation Task")
  assert_acceptance_equal(started.id, activation.causation_id, "Activation causation")
  assert_acceptance_equal(activation.id, completion.causation_id, "Completion causation")
  assert_acceptance_equal(
    [ lifecycle.first.correlation_id ],
    lifecycle.map(&:correlation_id).uniq,
    "Activated lifecycle correlation"
  )
  assert_acceptance_equal("activated", release_set_payload(completion).outcome, "Completion outcome")
end

Then("the completed activated ReleaseSet is available without a freshness gate") do
  content = release_set_view(@release_set_arguments.fetch(:release_set_id))
  release_set = content.dig("data", "release_set")
  assert_acceptance_equal("completed", release_set.fetch("status"), "ReleaseSet status")
  assert_acceptance_equal("activated", release_set.dig("completion", "outcome"), "Completion outcome")
  assert_acceptance_equal("production", release_set.dig("activation", "activation_point", "environment"), "Activation environment")
  assert_acceptance(
    (release_set.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Completed ReleaseSet must not expose a freshness gate"
  )
end

When("the first repository integrates while the second records failure through MCP") do
  release_set_id = @release_set_arguments.fetch(:release_set_id)
  prepared = release_set_payload(release_set_lifecycle_events(release_set_id).first)
  first = prepared.ordered_members.first
  submit_and_execute(
    "merge_observation_record",
    command_id: "cmd-cuc-compensation-observe",
    actor: { kind: "agent", id: "release-integrator-1" },
    merge_snapshot_id: first.merge_snapshot_id,
    authorization_event: first.authorization_event.to_h,
    authorization_decision_digest: first.authorization_decision_digest,
    repository_id: first.repository_id,
    target_branch: first.target_branch,
    object_format: first.object_format,
    target_before_commit_oid: first.target_base_commit_oid,
    target_after_commit_oid: first.merge_commit_oid,
    observer: { name: "release-adapter", version: "1.0.0" },
    run_id: "cuc-compensation-observation",
    observed_at: "2026-08-24T21:00:00.000000Z"
  )
  observation = event_store.read(
    streams.merge_snapshot(first.merge_snapshot_id),
    Coordinator::Write::EventQueries::MERGE_OBSERVATION
  ).sole
  observation_payload = release_set_payload(observation)
  @release_success_task_id = submit_and_execute(
    "release_repository_integration_record",
    command_id: "cmd-cuc-compensation-integrate-1",
    actor: { kind: "agent", id: "release-integrator-1" },
    release_set_id:,
    repository_id: first.repository_id,
    attempt_id: "cuc-compensation-attempt-1",
    outcome: "integrated",
    merge_observation_event: release_event_reference(observation).to_h,
    observation_digest: observation_payload.observation_digest,
    failure: nil
  )
  second = prepared.ordered_members.fetch(1)
  @release_failure_task_id = submit_and_execute(
    "release_repository_integration_record",
    command_id: "cmd-cuc-compensation-integrate-2",
    actor: { kind: "agent", id: "release-integrator-1" },
    release_set_id:,
    repository_id: second.repository_id,
    attempt_id: "cuc-compensation-attempt-2",
    outcome: "failed",
    merge_observation_event: nil,
    observation_digest: nil,
    failure: {
      code: "deployment-failed",
      summary: "Ledger deployment failed",
      producer: { name: "release-adapter", version: "1.0.0" },
      run_id: "cuc-compensation-failure",
      result_digest: "sha256:#{'d' * 64}",
      occurred_at: "2026-08-24T21:30:00.000000Z"
    }
  )
end

When("the ReleaseSet lifecycle Saga processes the failed integration twice") do
  failure = release_set_lifecycle_events(
    @release_set_arguments.fetch(:release_set_id)
  ).select { _1.type == "RepositoryIntegrationRecorded" }.last
  2.times { Coordinator::Container["process_managers.release_set_lifecycle"].call(failure) }
  @release_compensation_request_event = release_set_lifecycle_events(
    @release_set_arguments.fetch(:release_set_id)
  ).select { _1.type == "ReleaseSetCompensationRequested" }.sole
end

Then("one exact compensation request is durable with Saga tracing") do
  lifecycle = release_set_lifecycle_events(@release_set_arguments.fetch(:release_set_id))
  request = release_set_payload(@release_compensation_request_event)
  failure = lifecycle.select { _1.type == "RepositoryIntegrationRecorded" }.last
  assert_acceptance_equal(1, request.successful_integrations.length, "Compensation members")
  assert_acceptance_equal(release_event_reference(failure), request.trigger_event, "Compensation trigger")
  assert_acceptance_equal(failure.id, @release_compensation_request_event.causation_id, "Saga causation")
  assert_acceptance_equal(lifecycle.first.correlation_id, @release_compensation_request_event.correlation_id, "Saga correlation")
end

When("the agent records exact external compensation through MCP") do
  release_set_id = @release_set_arguments.fetch(:release_set_id)
  request = release_set_payload(@release_compensation_request_event)
  lifecycle = release_set_lifecycle_events(release_set_id)
  evidence = request.successful_integrations.map.with_index do |reference, index|
    integration = lifecycle.find { _1.id == reference.event_id }
    integration_payload = release_set_payload(integration)
    {
      repository_id: integration_payload.repository_id,
      integration_event: reference.to_h,
      action: "revert",
      external_reference: "reverts/cuc-compensation/#{index + 1}",
      result_digest: "sha256:#{'e' * 64}",
      producer: { name: "release-reverter", version: "1.0.0" },
      run_id: "cuc-compensation-run-#{index + 1}",
      compensated_at: "2026-08-24T22:30:0#{index}.000000Z"
    }
  end
  @release_compensation_task_id = submit_and_execute(
    "release_compensation_complete",
    command_id: "cmd-cuc-compensation-complete",
    actor: { kind: "agent", id: "release-operator-1" },
    release_set_id:,
    compensation_request_event: release_event_reference(@release_compensation_request_event).to_h,
    evidence:
  )
end

Then("the compensation Task completes the ReleaseSet with one physical correlation") do
  lifecycle = release_set_lifecycle_events(@release_set_arguments.fetch(:release_set_id))
  completion = lifecycle.select { _1.type == "ReleaseSetCompleted" }.sole
  started = task_events(@release_compensation_task_id).find do |event|
    event.type == "CoordinationTaskExecutionStarted"
  end
  state = task_request("tasks/get", @release_compensation_task_id)
  assert_acceptance_equal("completed", state.dig("result", "status"), "Compensation Task")
  assert_acceptance_equal(started.id, completion.causation_id, "Compensation completion causation")
  assert_acceptance_equal(
    [ lifecycle.first.correlation_id ],
    lifecycle.map(&:correlation_id).uniq,
    "Compensated lifecycle correlation"
  )
  assert_acceptance_equal("compensated", release_set_payload(completion).outcome, "Completion outcome")
end

Then("the completed compensated ReleaseSet is available without a freshness gate") do
  content = release_set_view(@release_set_arguments.fetch(:release_set_id))
  release_set = content.dig("data", "release_set")
  assert_acceptance_equal("completed", release_set.fetch("status"), "ReleaseSet status")
  assert_acceptance_equal("compensated", release_set.dig("completion", "outcome"), "Completion outcome")
  assert_acceptance_equal(1, release_set.dig("completion", "compensation_evidence").length, "Evidence count")
  assert_acceptance(
    (release_set.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Completed ReleaseSet must not expose a freshness gate"
  )
end
