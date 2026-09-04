# frozen_string_literal: true

module ReleaseSetScenario
  module_function

  REPOSITORIES = %w[billing ledger].freeze

  def prepare_input(prefix:, dependency: nil, omit_completed_member: false)
    authorizations = authorized_members(prefix:, dependency:, omit_completed_member:)
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

  def prepare(prefix:, dependency: nil, omit_completed_member: false)
    input = prepare_input(prefix:, dependency:, omit_completed_member:)
    completion = execute(Coordinator::Write::Operations::ExecutePrepareReleaseSet, input)
    event = event_store.read(
      streams.release_set(input.fetch(:release_set_id)),
      Coordinator::Write::EventQueries::RELEASE_SET_PREPARATION
    ).find { _1.type == "ReleaseSetPrepared" }
    { input:, completion:, event:, payload: completion.data, dependency: }
  end

  def observe_member(prepared, index:, prefix:)
    member = prepared.fetch(:input).fetch(:ordered_members).fetch(index)
    snapshot = Coordinator::Write::MergeSnapshots::StateLoader.new(event_store:).call(
      member.fetch(:merge_snapshot_id)
    )
    input = {
      command_id: "cmd-release-observe-#{prefix}-#{index + 1}",
      actor: { kind: "agent", id: "release-integrator-1" },
      merge_snapshot_id: member.fetch(:merge_snapshot_id),
      authorization_event: member.fetch(:authorization_event),
      authorization_decision_digest: member.fetch(:authorization_decision_digest),
      repository_id: member.fetch(:repository_id),
      target_branch: member.fetch(:target_branch),
      object_format: member.fetch(:object_format),
      target_before_commit_oid: snapshot.target_base_commit_oid,
      target_after_commit_oid: snapshot.merge_commit_oid,
      observer: { name: "release-adapter", version: "1.0.0" },
      run_id: "release-observation-#{prefix}-#{index + 1}",
      observed_at: "2026-08-24T19:00:0#{index}.000000Z"
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRecordMergeObservation, input)
    event = event_store.read(
      streams.merge_snapshot(member.fetch(:merge_snapshot_id)),
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
      observation_digest: observation&.dig(:completion)&.data&.observation_digest,
      failure: failure
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRecordRepositoryIntegration, input)
    event = release_lifecycle_events(prepared.dig(:input, :release_set_id)).reverse.find do |candidate|
      candidate.type == "RepositoryIntegrationRecorded" && candidate.id == completion.data.integration_event.event_id
    end
    { input:, completion:, event:, payload: completion.data }
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
    event = release_lifecycle_events(prepared.dig(:input, :release_set_id)).reverse.find do |candidate|
      candidate.type == "ReleaseSetVerificationRecorded" && candidate.id == completion.data.verification_event.event_id
    end
    { input:, completion:, event:, payload: completion.data }
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
        run_id: "release-activation-#{prefix}"
      }
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRecordReleaseSetActivation, input)
    event = release_lifecycle_events(prepared.dig(:input, :release_set_id)).last
    { input:, completion:, event:, payload: completion.data }
  end

  def complete_compensation(prepared, request:, prefix:)
    state = Coordinator::Write::ReleaseSets::HistoryLoader.new(event_store:).call(
      prepared.dig(:input, :release_set_id)
    )
    evidence = state.compensation_request.successful_integrations.map.with_index do |reference, index|
      integration = state.integrations.find { _1.event == reference }
      {
        repository_id: integration.payload.repository_id,
        integration_event: reference.to_h,
        action: "revert",
        external_reference: "reverts/#{prefix}/#{index + 1}",
        result_digest: "sha256:#{(index + 5).to_s * 64}",
        producer: { name: "release-reverter", version: "1.0.0" },
        run_id: "release-compensation-#{prefix}-#{index + 1}"
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
    { input:, completion:, event:, payload: completion.data }
  end

  def authorized_members(prefix:, dependency: nil, omit_completed_member: false)
    candidates = candidates(prefix:, dependency:, extra_completed_member: omit_completed_member)
    candidates = candidates.first(REPOSITORIES.length) if omit_completed_member
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

  def candidates(prefix:, dependency: nil, extra_completed_member: false)
    change_set_id = "CS-release-#{prefix}"
    create_change_set(prefix:, change_set_id:)
    repositories = extra_completed_member ? REPOSITORIES + [ "audit" ] : REPOSITORIES
    work = repositories.each_with_index.map do |repository_name, index|
      repository_id = RepositoryScenario.repository_id(repository_name)
      RepositoryScenario.register(event_store:, key: repository_name, repository_id:)
      create_work_item(
        prefix:,
        change_set_id:,
        repository_id:,
        repository_name:,
        index: index + 1
      )
    end
    create_release_dependency(prefix:, change_set_id:, producer: work.fetch(0), dependency:) if dependency
    activate(change_set_id:, prefix:)
    work.map do |member|
      candidate = submit_candidate(prefix:, change_set_id:, **member)
      complete_candidate(candidate, prefix:, index: member.fetch(:index))
    end
  end

  def create_release_dependency(prefix:, change_set_id:, producer:, dependency:)
    consumer = create_work_item(
      prefix:,
      change_set_id:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      repository_name: "billing",
      index: "consumer"
    )
    execute(Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency, {
      command_id: "seed-release-dependency-#{prefix}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      dependency_id: "DEP-release-#{prefix}",
      producer_work_item_id: producer.fetch(:work_item_id),
      consumer_work_item_id: consumer.fetch(:work_item_id),
      dependency_kind: dependency.fetch(:kind),
      required_output: dependency[:required_output]
    })
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

  def create_work_item(prefix:, change_set_id:, repository_id:, repository_name:, index:)
    work_item_id = "W-release-#{prefix}-#{index}"
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "seed-release-work-#{prefix}-#{index}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id:,
      goal: "Produce #{repository_name} release Candidate",
      acceptance_criteria: [ "Candidate is checkpointed" ]
    })
    { repository_id:, repository_name:, work_item_id:, index: }
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

  def submit_candidate(prefix:, change_set_id:, repository_id:, repository_name:, work_item_id:, index:)
    attempt_id = "A-release-#{prefix}-#{index}"
    identity_seed = prefix.bytes.sum * 100 + index
    base_oid = format("%040x", identity_seed)
    head_oid = format("%040x", identity_seed + 10_000)
    path = "lib/#{repository_name}.rb"
    resource_id = ResourceScenario.resolve(event_store:, repository_id:, kind: "file", path:)
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
      resources: [ { resource_id:, base_blob_oid: "a" * 40 } ],
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
          resource_id: reference.resource_id,
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
    { input:, completion:, reservation: }
  end

  def complete_candidate(candidate, prefix:, index:)
    input = candidate.fetch(:input)
    reservation = candidate.fetch(:reservation)
    execute(Coordinator::Write::Operations::ExecuteReleaseLeaseSet, {
      command_id: "seed-release-lease-release-#{prefix}-#{index}",
      actor: input.fetch(:actor),
      change_set_id: input.fetch(:change_set_id),
      work_item_id: input.fetch(:work_item_id),
      attempt_id: input.fetch(:attempt_id),
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |lease|
        {
          resource_id: lease.resource_id,
          lease_id: lease.lease_id,
          fencing_token: lease.fencing_token
        }
      end
    })
    work_item_completion = execute(Coordinator::Write::Operations::ExecuteCompleteWorkItem, {
      command_id: "seed-release-work-complete-#{prefix}-#{index}",
      actor: input.fetch(:actor),
      change_set_id: input.fetch(:change_set_id),
      work_item_id: input.fetch(:work_item_id),
      attempt_id: input.fetch(:attempt_id),
      candidate_id: input.fetch(:candidate_id),
      produced_outputs: []
    })
    candidate.merge(work_item_completion:)
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
