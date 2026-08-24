# frozen_string_literal: true

module ReleaseSetScenario
  module_function

  REPOSITORIES = %w[billing ledger].freeze

  def prepare_input(prefix:)
    authorizations = authorized_members(prefix:)
    {
      command_id: "cmd-release-prepare-#{prefix}",
      actor: { kind: "agent", id: "release-coordinator-1" },
      release_set_id: "REL-#{prefix}",
      ordered_members: authorizations.map do |entry|
        registration = entry.fetch(:registration)
        authorization = entry.fetch(:authorization)
        snapshot = registration.fetch(:input)
        decision = authorization.fetch(:completion).data
        {
          repository_id: snapshot.fetch(:repository_id),
          target_branch: snapshot.fetch(:target_branch),
          object_format: "sha1",
          merge_snapshot_id: snapshot.fetch(:merge_snapshot_id),
          snapshot_binding: authorization.fetch(:payload).snapshot_binding.to_h,
          authorization_event: decision.decision_event.to_h,
          authorization_decision_digest: decision.decision_digest
        }
      end
    }
  end

  def prepare(prefix:)
    input = prepare_input(prefix:)
    completion = execute(Coordinator::Write::Operations::ExecutePrepareReleaseSet, input)
    event = event_store.read(
      streams.release_set(input.fetch(:release_set_id)),
      Coordinator::Write::EventQueries::RELEASE_SET_PREPARATION
    ).sole
    { input:, completion:, event:, payload: load(event) }
  end

  def observe_member(prepared, index:, prefix:)
    member = prepared.fetch(:payload).ordered_members.fetch(index)
    input = {
      command_id: "cmd-release-observe-#{prefix}-#{index + 1}",
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
      run_id: "release-observation-#{prefix}-#{index + 1}",
      observed_at: "2026-08-24T19:00:0#{index}.000000Z"
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRecordMergeObservation, input)
    event = event_store.read(
      streams.merge_snapshot(member.merge_snapshot_id),
      Coordinator::Write::EventQueries::MERGE_OBSERVATION
    ).sole
    { input:, completion:, event:, payload: load(event) }
  end

  def record_integration(prepared, index:, prefix:, observation: nil, failure: nil)
    member = prepared.fetch(:payload).ordered_members.fetch(index)
    input = {
      command_id: "cmd-release-integrate-#{prefix}-#{index + 1}",
      actor: { kind: "agent", id: "release-integrator-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      repository_id: member.repository_id,
      attempt_id: "release-attempt-#{prefix}-#{index + 1}",
      outcome: observation ? "integrated" : "failed",
      merge_observation_event: observation&.dig(:completion)&.data&.observation_event&.to_h,
      observation_digest: observation&.dig(:payload)&.observation_digest,
      failure: failure
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRecordRepositoryIntegration, input)
    event = release_lifecycle_events(prepared.dig(:input, :release_set_id)).last
    { input:, completion:, event:, payload: load(event) }
  end

  def integrate_all(prepared, prefix:)
    prepared.fetch(:payload).ordered_members.each_index.map do |index|
      observation = observe_member(prepared, index:, prefix:)
      record_integration(prepared, index:, prefix:, observation:)
    end
  end

  def record_verification(prepared, integrations:, prefix:, outcome: "passed", findings: [])
    input = {
      command_id: "cmd-release-verify-#{prefix}",
      actor: { kind: "agent", id: "release-verifier-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      integration_events: integrations.map { _1.fetch(:completion).data.integration_event.to_h },
      evidence: {
        producer: { name: "release-suite", version: "1.0.0" },
        run_id: "release-verification-#{prefix}",
        environment_digest: "sha256:#{'e' * 64}",
        result_digest: "sha256:#{outcome == 'passed' ? 'f' * 64 : 'd' * 64}",
        outcome:,
        findings:,
        produced_at: "2026-08-24T20:00:00.000000Z"
      }
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRecordReleaseSetVerification, input)
    event = release_lifecycle_events(prepared.dig(:input, :release_set_id)).last
    { input:, completion:, event:, payload: load(event) }
  end

  def record_activation(prepared, verification:, prefix:)
    input = {
      command_id: "cmd-release-activate-set-#{prefix}",
      actor: { kind: "agent", id: "release-operator-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      verification_event: verification.fetch(:completion).data.verification_event.to_h,
      verification_digest: verification.fetch(:payload).verification_digest,
      activation_point: {
        kind: "deployment_manifest",
        environment: "production",
        external_reference: "deployments/#{prefix}",
        state_digest: "sha256:#{'a' * 64}",
        producer: { name: "deployment-controller", version: "1.0.0" },
        run_id: "release-activation-#{prefix}",
        activated_at: "2026-08-24T21:00:00.000000Z"
      }
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRecordReleaseSetActivation, input)
    event = release_lifecycle_events(prepared.dig(:input, :release_set_id)).last
    { input:, completion:, event:, payload: load(event) }
  end

  def complete_compensation(prepared, request:, prefix:)
    state = Coordinator::Write::ReleaseSets::HistoryLoader.new(event_store:).call(
      prepared.dig(:input, :release_set_id)
    )
    evidence = request.fetch(:payload).successful_integrations.map.with_index do |reference, index|
      integration = state.integrations.find { _1.event == reference }
      {
        repository_id: integration.payload.repository_id,
        integration_event: reference.to_h,
        action: "revert",
        external_reference: "reverts/#{prefix}/#{index + 1}",
        result_digest: "sha256:#{(index + 5).to_s * 64}",
        producer: { name: "release-reverter", version: "1.0.0" },
        run_id: "release-compensation-#{prefix}-#{index + 1}",
        compensated_at: "2026-08-24T22:00:0#{index}.000000Z"
      }
    end
    input = {
      command_id: "cmd-release-compensation-complete-#{prefix}",
      actor: { kind: "agent", id: "release-operator-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      compensation_request_event: request.fetch(:event).then { reference(_1).to_h },
      evidence:
    }
    completion = execute(Coordinator::Write::Operations::ExecuteCompleteCompensatedReleaseSet, input)
    event = release_lifecycle_events(prepared.dig(:input, :release_set_id)).last
    { input:, completion:, event:, payload: load(event) }
  end

  def authorized_members(prefix:)
    candidates = candidates(prefix:)
    candidates.each_with_index.map do |candidate, index|
      member_prefix = "#{prefix}-#{index + 1}"
      registration = MergeSnapshotScenario.register_candidates(
        prefix: member_prefix,
        candidates: [ candidate ]
      )
      verification = MergeSnapshotScenario.verify(registration, prefix: member_prefix)
      authorization = MergeSnapshotScenario.authorize(
        registration,
        verification,
        prefix: member_prefix
      )
      { registration:, verification:, authorization: }
    end
  end

  def candidates(prefix:)
    change_set_id = "CS-release-#{prefix}"
    create_change_set(prefix:, change_set_id:)
    work = REPOSITORIES.each_with_index.map do |repository_id, index|
      create_work_item(prefix:, change_set_id:, repository_id:, index: index + 1)
    end
    activate(change_set_id:, prefix:)
    work.map { submit_candidate(prefix:, change_set_id:, **_1) }
  end

  def create_change_set(prefix:, change_set_id:)
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "seed-release-create-#{prefix}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate one multi-repository release",
      acceptance_criteria: [ "Both repositories use one immutable release plan" ]
    })
  end

  def create_work_item(prefix:, change_set_id:, repository_id:, index:)
    work_item_id = "W-release-#{prefix}-#{index}"
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "seed-release-work-#{prefix}-#{index}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id:,
      goal: "Produce #{repository_id} release Candidate",
      acceptance_criteria: [ "Candidate is checkpointed" ]
    })
    { repository_id:, work_item_id:, index: }
  end

  def activate(change_set_id:, prefix:)
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "seed-release-activate-#{prefix}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:
    })
    activation = event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
  end

  def submit_candidate(prefix:, change_set_id:, repository_id:, work_item_id:, index:)
    attempt_id = "A-release-#{prefix}-#{index}"
    base_oid = index.to_s * 40
    head_oid = (index + 2).to_s * 40
    path = "lib/#{repository_id}.rb"
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "seed-release-acquire-#{prefix}-#{index}",
      actor: { kind: "agent", id: "agent-#{index}" },
      change_set_id:,
      work_item_id:,
      attempt_id:,
      base_snapshots: [ { repository_id:, commit_oid: base_oid } ]
    })
    reservation = execute(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "seed-release-reserve-#{prefix}-#{index}",
      actor: { kind: "agent", id: "agent-#{index}" },
      change_set_id:,
      work_item_id:,
      attempt_id:,
      repository_id:,
      base_commit_oid: base_oid,
      resources: [ { kind: "file", path:, base_blob_oid: "a" * 40 } ],
      lease_duration_seconds: 900
    }).data
    input = {
      command_id: "seed-release-candidate-#{prefix}-#{index}",
      actor: { kind: "agent", id: "agent-#{index}" },
      candidate_id: "CAN-release-#{prefix}-#{index}",
      change_set_id:,
      work_item_id:,
      attempt_id:,
      repository_id:,
      target_branch: "main",
      base_commit_oid: base_oid,
      head_commit_oid: head_oid,
      checkpoint_kind: "final",
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |reference|
        {
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end,
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [
          CandidateScenario.manifest_file(path).merge(
            old_blob_oid: "a" * 40,
            new_blob_oid: "b" * 40
          )
        ]
      }
    }
    completion = execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
    { input:, completion: }
  end

  def execute(operation_class, input)
    result = operation_class.new(event_store:).call(input)
    raise result.failure.inspect if result.failure?

    result.value!
  end

  def event_store
    Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def release_lifecycle_events(release_set_id)
    event_store.read(streams.release_set(release_set_id), Coordinator::Write::EventQueries::RELEASE_SET_LIFECYCLE)
  end

  def streams
    Coordinator::Write::StreamFactory.new
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end
end
