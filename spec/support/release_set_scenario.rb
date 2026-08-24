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
end
