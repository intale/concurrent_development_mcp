# frozen_string_literal: true

module SagaIdentityAcceptanceWorld
  def prepare_batch_process_identity
    @saga_identity_kind = :batch
    @operation_batch_id = SecureRandom.uuid_v7
    item = batch_skill_item(index: 0, name: "reserved-batch-process-command")
    submit_skill_batch([ item ], pause_at: "operation_batch_page_start")
    await_contention_evidence
    creation = operation_batch_events.find { _1.type == "OperationBatchCreated" }
    assert_acceptance(creation, "The accepted Batch has no creation fact")
    @reserved_internal_command_id = [
      "internal:batch:outcome",
      @operation_batch_id,
      creation.id,
      0
    ].join(":")
  end

  def prepare_prior_target_for_batch_replay
    @operation_batch_id = SecureRandom.uuid_v7
    @prior_batch_item = batch_skill_item(
      index: 0,
      name: "prior-command-batch-replay"
    ).merge(command_id: "cmd-cuc-prior-target-#{@operation_batch_id}")
    state = complete_saga_task(
      "skill_publish",
      client_id: "prior-target-agent",
      **@prior_batch_item
    )
    @prior_target_completion = command_events(@prior_batch_item.fetch(:command_id)).sole
    assert_acceptance_equal(
      false,
      state.dig("result", "result", "isError"),
      "Prior target command"
    )
  end

  def process_prior_target_through_batch
    submit_skill_batch([ @prior_batch_item ], pause_at: "operation_batch_page")
    await_contention_evidence
    @batch_history_before_redelivery = operation_batch_events
    restart_operation_batch_after_page
    @batch_history_after_redelivery = operation_batch_events
  end

  def prepare_release_process_identity
    @saga_identity_kind = :release
    prefix = SecureRandom.uuid_v7.delete("-").first(12)
    repositories = %w[one two].map do |role|
      register_acceptance_repository("saga-release-#{prefix}-#{role}")
    end
    change_set_id = "CS-CUC-SAGA-REL-#{prefix}"
    work_items = repositories.each_with_index.map do |repository_id, index|
      {
        repository_id:,
        work_item_id: "W-CUC-SAGA-REL-#{prefix}-#{index + 1}",
        attempt_id: "A-CUC-SAGA-REL-#{prefix}-#{index + 1}",
        candidate_id: "CAN-CUC-SAGA-REL-#{prefix}-#{index + 1}",
        path: "lib/saga_release_#{prefix}_#{index + 1}.rb"
      }
    end

    complete_saga_task(
      "change_set_create",
      command_id: "cmd-cuc-saga-rel-#{prefix}-create",
      actor: { kind: "agent", id: "saga-planner" },
      change_set_id:,
      goal: "Coordinate a ReleaseSet process identity",
      acceptance_criteria: [ "Every lifecycle decision remains system-owned" ]
    )
    work_items.each_with_index do |item, index|
      complete_saga_task(
        "work_item_create",
        command_id: "cmd-cuc-saga-rel-#{prefix}-work-#{index + 1}",
        actor: { kind: "agent", id: "saga-planner" },
        change_set_id:,
        work_item_id: item.fetch(:work_item_id),
        repository_id: item.fetch(:repository_id),
        goal: "Prepare ReleaseSet member #{index + 1}",
        acceptance_criteria: [ "The member has exact integration evidence" ]
      )
    end
    complete_saga_task(
      "change_set_activate",
      command_id: "cmd-cuc-saga-rel-#{prefix}-activate",
      actor: { kind: "agent", id: "saga-planner" },
      change_set_id:
    )
    work_items.each { await_work_item_ready(_1.fetch(:work_item_id)) }

    members = work_items.each_with_index.map do |item, index|
      prepare_release_member(
        prefix:,
        change_set_id:,
        item:,
        index:
      )
    end
    @release_set_id = "RS-CUC-SAGA-REL-#{prefix}"
    complete_saga_task(
      "release_set_prepare",
      command_id: "cmd-cuc-saga-rel-#{prefix}-prepare",
      actor: { kind: "agent", id: "saga-integrator" },
      release_set_id: @release_set_id,
      ordered_members: members.map { _1.fetch(:release_member) }
    )
    record_successful_release_integration(prefix:, member: members.first)

    failure_command_id = "cmd-cuc-saga-rel-#{prefix}-failure"
    install_contention_barrier(
      operation: "release_set_lifecycle",
      command_ids: [ failure_command_id ]
    )
    complete_saga_task(
      "release_repository_integration_record",
      command_id: failure_command_id,
      actor: { kind: "agent", id: "saga-integrator" },
      release_set_id: @release_set_id,
      repository_id: members.fetch(1).dig(:release_member, :repository_id),
      attempt_id: "release-attempt-#{prefix}-2",
      outcome: "failed",
      merge_observation_event: nil,
      observation_digest: nil,
      failure: {
        code: "integration-failed",
        summary: "The second repository integration failed.",
        producer: { name: "saga-release-adapter", version: "1.0.0" },
        run_id: "saga-release-failure-#{prefix}",
        result_digest: "sha256:#{'f' * 64}",
        occurred_at: "2026-08-27T12:30:00.000000Z"
      }
    )
    evidence = await_contention_evidence.sole
    @reserved_internal_command_id = evidence.fetch(:process_command_id)
    assert_acceptance(
      @reserved_internal_command_id&.start_with?("internal:release-compensation:v1:"),
      "ReleaseSet lifecycle exposed no reserved process command: #{evidence.inspect}"
    )
  end

  def submit_reserved_internal_identity
    @reserved_internal_response = call_tool(
      "change_set_create",
      {
        command_id: @reserved_internal_command_id,
        actor: { kind: "agent", id: "identity-preemption-agent" },
        change_set_id: "CS-CUC-INTERNAL-PREEMPT-#{SecureRandom.uuid_v7}",
        goal: "This public request must not allocate a Task.",
        acceptance_criteria: [ "The process command namespace remains reserved." ]
      },
      client_id: "identity-preemption-agent"
    )
  end

  def finish_paused_saga
    release_contention_barrier
    if @saga_identity_kind == :batch
      await_operation_batch_terminal
    else
      finish_compensated_release_set
    end
  end

  private

  def complete_saga_task(tool, client_id: "saga-agent", **arguments)
    task_id = submit_and_execute(tool, client_id:, **arguments)
    assert_successful_task(task_id, "Saga setup #{tool}")
  end

  def prepare_release_member(prefix:, change_set_id:, item:, index:)
    agent_id = "saga-member-#{index + 1}"
    complete_saga_task(
      "work_item_acquire",
      command_id: "cmd-cuc-saga-rel-#{prefix}-acquire-#{index + 1}",
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id: item.fetch(:work_item_id),
      attempt_id: item.fetch(:attempt_id),
      base_snapshots: [
        {
          repository_id: item.fetch(:repository_id),
          commit_oid: CandidateAcceptanceWorld::BASE_COMMIT_OID
        }
      ]
    )
    reservation_state = complete_saga_task(
      "write_set_reserve",
      command_id: "cmd-cuc-saga-rel-#{prefix}-reserve-#{index + 1}",
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id: item.fetch(:work_item_id),
      attempt_id: item.fetch(:attempt_id),
      repository_id: item.fetch(:repository_id),
      base_commit_oid: CandidateAcceptanceWorld::BASE_COMMIT_OID,
      resources: [
        resource_target(
          kind: "file",
          path: item.fetch(:path),
          repository_id: item.fetch(:repository_id),
          base_blob_oid: CandidateAcceptanceWorld::BASE_BLOB_OID,
          actor_id: agent_id
        )
      ],
      lease_duration_seconds: 900
    )
    reservation = reservation_state.dig("result", "result", "structuredContent", "data")
    coordination = {
      agent_id:,
      path: item.fetch(:path),
      repository_id: item.fetch(:repository_id),
      ids: {
        change_set_id:,
        work_item_id: item.fetch(:work_item_id),
        attempt_id: item.fetch(:attempt_id)
      },
      reservation:
    }
    candidate = candidate_arguments(
      coordination,
      candidate_id: item.fetch(:candidate_id),
      command_id: "cmd-cuc-saga-rel-#{prefix}-candidate-#{index + 1}",
      head_character: (index.zero? ? "b" : "c")
    )
    candidate_state = complete_saga_task("candidate_submit", **candidate)
    assert_acceptance_equal(
      item.fetch(:candidate_id),
      candidate_state.dig("result", "result", "structuredContent", "data", "candidate_id"),
      "Release member Candidate"
    )
    complete_saga_task(
      "lease_release",
      command_id: "cmd-cuc-saga-rel-#{prefix}-release-#{index + 1}",
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id: item.fetch(:work_item_id),
      attempt_id: item.fetch(:attempt_id),
      lease_set_id: reservation.fetch("lease_set_id"),
      leases: reservation.fetch("resources").map do |reference|
        {
          resource_id: reference.fetch("resource_id"),
          lease_id: reference.fetch("lease_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end
    )
    complete_saga_task(
      "work_item_complete",
      command_id: "cmd-cuc-saga-rel-#{prefix}-complete-#{index + 1}",
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id: item.fetch(:work_item_id),
      attempt_id: item.fetch(:attempt_id),
      candidate_id: item.fetch(:candidate_id),
      produced_outputs: []
    )
    prepare_merge_grant(prefix:, candidate:, index:)
  end

  def prepare_merge_grant(prefix:, candidate:, index:)
    snapshot_id = "MS-CUC-SAGA-REL-#{prefix}-#{index + 1}"
    snapshot_arguments = {
      command_id: "cmd-cuc-saga-rel-#{prefix}-snapshot-#{index + 1}",
      actor: { kind: "agent", id: "saga-integrator" },
      merge_snapshot_id: snapshot_id,
      repository_id: candidate.fetch(:repository_id),
      target_branch: candidate.fetch(:target_branch),
      target_base_commit_oid: candidate.fetch(:base_commit_oid),
      ordered_candidates: [
        {
          candidate_id: candidate.fetch(:candidate_id),
          head_commit_oid: candidate.fetch(:head_commit_oid)
        }
      ],
      merge_commit_oid: (index.zero? ? "8" : "9") * 40,
      producer: { name: "saga-git-merge", version: "1.0.0" },
      run_id: "saga-merge-#{prefix}-#{index + 1}",
      produced_at: "2026-08-27T10:00:0#{index}.000000Z"
    }
    registration_state = complete_saga_task("merge_snapshot_register", **snapshot_arguments)
    registration = registration_state.dig("result", "result", "structuredContent", "data")
    verification_arguments = {
      command_id: "cmd-cuc-saga-rel-#{prefix}-verify-#{index + 1}",
      actor: { kind: "agent", id: "saga-verifier" },
      merge_snapshot_id: snapshot_id,
      binding: {
        snapshot_event: registration.fetch("snapshot_event"),
        snapshot_digest: registration.fetch("snapshot_digest"),
        repository_id: snapshot_arguments.fetch(:repository_id),
        target_branch: snapshot_arguments.fetch(:target_branch),
        object_format: "sha1",
        target_base_commit_oid: snapshot_arguments.fetch(:target_base_commit_oid),
        ordered_candidates: snapshot_arguments.fetch(:ordered_candidates),
        merge_commit_oid: snapshot_arguments.fetch(:merge_commit_oid)
      },
      assessment: {
        evidence_kind: "combined_tests",
        producer: { name: "saga-verifier", version: "1.0.0" },
        run_id: "saga-verification-#{prefix}-#{index + 1}",
        test_suite_digest: "sha256:#{'a' * 64}",
        environment_digest: "sha256:#{'b' * 64}",
        result_digest: "sha256:#{'c' * 64}",
        conclusion: "passed",
        findings: [],
        produced_at: "2026-08-27T10:30:0#{index}.000000Z"
      }
    }
    complete_saga_task("merge_verification_submit", **verification_arguments)
    verified = merge_snapshot_events(snapshot_id).find { _1.type == "MergeSnapshotVerified" }
    assert_acceptance(verified, "Merge snapshot #{snapshot_id} has no verified fact")
    authorization_state = complete_saga_task(
      "merge_authorization_request",
      command_id: "cmd-cuc-saga-rel-#{prefix}-authorize-#{index + 1}",
      actor: { kind: "agent", id: "saga-integrator" },
      merge_snapshot_id: snapshot_id,
      snapshot_binding: {
        registration_event: registration.fetch("snapshot_event"),
        snapshot_digest: registration.fetch("snapshot_digest"),
        verification_event: saga_event_reference(verified),
        verification_digest: verified.data.fetch("verification_digest")
      },
      target_base_observation: {
        repository_id: snapshot_arguments.fetch(:repository_id),
        target_branch: snapshot_arguments.fetch(:target_branch),
        object_format: "sha1",
        commit_oid: snapshot_arguments.fetch(:target_base_commit_oid),
        observer: { name: "saga-git-fetch", version: "1.0.0" },
        run_id: "saga-base-#{prefix}-#{index + 1}",
        observed_at: "2026-08-27T10:45:0#{index}.000000Z"
      },
      expected_impact_policy: nil
    )
    authorization = authorization_state.dig("result", "result", "structuredContent", "data")
    assert_acceptance_equal("granted", authorization.fetch("outcome"), "Merge authorization")
    {
      snapshot_arguments:,
      authorization:,
      release_member: {
        repository_id: snapshot_arguments.fetch(:repository_id),
        target_branch: snapshot_arguments.fetch(:target_branch),
        object_format: "sha1",
        merge_snapshot_id: snapshot_id,
        snapshot_binding: {
          registration_event: registration.fetch("snapshot_event"),
          snapshot_digest: registration.fetch("snapshot_digest"),
          verification_event: saga_event_reference(verified),
          verification_digest: verified.data.fetch("verification_digest")
        },
        authorization_event: authorization.fetch("decision_event"),
        authorization_decision_digest: authorization.fetch("decision_digest")
      }
    }
  end

  def record_successful_release_integration(prefix:, member:)
    snapshot = member.fetch(:snapshot_arguments)
    authorization = member.fetch(:authorization)
    complete_saga_task(
      "merge_observation_record",
      command_id: "cmd-cuc-saga-rel-#{prefix}-observe-1",
      actor: { kind: "agent", id: "saga-integrator" },
      merge_snapshot_id: snapshot.fetch(:merge_snapshot_id),
      authorization_event: authorization.fetch("decision_event"),
      authorization_decision_digest: authorization.fetch("decision_digest"),
      repository_id: snapshot.fetch(:repository_id),
      target_branch: snapshot.fetch(:target_branch),
      object_format: "sha1",
      target_before_commit_oid: snapshot.fetch(:target_base_commit_oid),
      target_after_commit_oid: snapshot.fetch(:merge_commit_oid),
      observer: { name: "saga-release-adapter", version: "1.0.0" },
      run_id: "saga-observation-#{prefix}",
      observed_at: "2026-08-27T11:30:00.000000Z"
    )
    observation = merge_snapshot_events(snapshot.fetch(:merge_snapshot_id)).find do |event|
      event.type == "MergeObserved"
    end
    assert_acceptance(observation, "The first ReleaseSet member has no merge observation")
    complete_saga_task(
      "release_repository_integration_record",
      command_id: "cmd-cuc-saga-rel-#{prefix}-integration-1",
      actor: { kind: "agent", id: "saga-integrator" },
      release_set_id: @release_set_id,
      repository_id: snapshot.fetch(:repository_id),
      attempt_id: "release-attempt-#{prefix}-1",
      outcome: "integrated",
      merge_observation_event: saga_event_reference(observation),
      observation_digest: observation.data.fetch("observation_digest"),
      failure: nil
    )
  end

  def finish_compensated_release_set
    request_event = eventually("ReleaseSet #{@release_set_id} compensation request") do
      event = release_set_lifecycle_events(@release_set_id).find do |candidate|
        candidate.type == "ReleaseSetCompensationRequested"
      end
      [ !event.nil?, event ]
    end
    request = release_set_payload(request_event)
    lifecycle = release_set_lifecycle_events(@release_set_id)
    evidence = request.successful_integrations.map.with_index do |reference, index|
      integration = lifecycle.find { _1.id == reference.event_id }
      payload = release_set_payload(integration)
      {
        repository_id: payload.repository_id,
        integration_event: reference.to_h,
        action: "revert",
        external_reference: "reverts/saga-identity/#{index + 1}",
        result_digest: "sha256:#{'e' * 64}",
        producer: { name: "saga-reverter", version: "1.0.0" },
        run_id: "saga-revert-#{index + 1}",
        compensated_at: "2026-08-27T13:00:0#{index}.000000Z"
      }
    end
    complete_saga_task(
      "release_compensation_complete",
      command_id: "cmd-cuc-saga-compensate-#{@release_set_id}",
      actor: { kind: "agent", id: "saga-integrator" },
      release_set_id: @release_set_id,
      compensation_request_event: saga_event_reference(request_event),
      evidence:
    )
    eventually("ReleaseSet #{@release_set_id} terminal completion") do
      events = release_set_lifecycle_events(@release_set_id)
      [ events.any? { _1.type == "ReleaseSetCompleted" }, events.map(&:type) ]
    end
  end

  def merge_snapshot_events(snapshot_id)
    event_store.read(
      streams.merge_snapshot(snapshot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          MergeSnapshotRegistered
          MergeSnapshotVerificationSubmitted
          MergeSnapshotVerified
          MergeObserved
        ],
        maximum_count: 36,
        direction: :asc
      )
    )
  end

  def saga_event_reference(event)
    {
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    }
  end
end

World(SagaIdentityAcceptanceWorld)
