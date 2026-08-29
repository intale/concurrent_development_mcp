# frozen_string_literal: true

module CandidateScenario
  REPOSITORY_ID = "01a03deb-6f55-74ba-bcc0-afd02e7b14dc"

  module_function

  def prepare(prefix:, path: "lib/candidate.rb", agent_id: "agent-a", head_commit_oid: "b" * 40)
    ids = {
      change_set_id: "CS-#{prefix}",
      work_item_id: "W-#{prefix}",
      attempt_id: "A-#{prefix}"
    }
    seed_attempt(ids:, agent_id:)
    resource_id = ResourceScenario.resolve(
      event_store:,
      repository_id: REPOSITORY_ID,
      kind: "file",
      path:
    )
    reservation = execute(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "seed-reserve-#{prefix}",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ { resource_id:, base_blob_oid: "c" * 40 } ],
      lease_duration_seconds: 900
    }).data

    {
      ids:,
      reservation:,
      input: input(
        prefix:,
        ids:,
        reservation:,
        path:,
        agent_id:,
        candidate_id: "CAN-#{prefix}",
        command_id: "cmd-#{prefix}",
        head_commit_oid:
      )
    }
  end

  def submit(prefix:, build_context: true, path: "lib/candidate.rb", head_commit_oid: "b" * 40)
    prepared = prepare(prefix:, path:, head_commit_oid:)
    input = prepared.fetch(:input)
    input = input.merge(build_context: build_context_for(path)) if build_context
    completion = execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
    prepared.merge(
      input:,
      completion:,
      events: candidate_events(input.fetch(:candidate_id)),
      attachment: attachment_events(prepared.dig(:ids, :attempt_id)).last
    )
  end

  def impact_input(candidate, command_id: nil, surface: nil, actor_id: "analyzer-7")
    input = candidate.fetch(:input)
    manifest = candidate.fetch(:events).find { _1.type == "CandidateChangeManifestCaptured" }
    context = candidate.fetch(:events).find { _1.type == "CandidateBuildContextCaptured" }
    {
      command_id: command_id || "cmd-impact-#{input.fetch(:candidate_id)}",
      actor: { kind: "agent", id: actor_id },
      candidate_id: input.fetch(:candidate_id),
      repository_id: input.fetch(:repository_id),
      head_commit_oid: input.fetch(:head_commit_oid),
      manifest_digest: manifest.data.fetch("manifest_digest"),
      build_context_digest: context&.data&.fetch("build_context_digest"),
      analyzer_version: "impact-analyzer-v1",
      surface: surface || {
        produces: [ { impact_key: "contract:payments-api:v2", after: "available" } ],
        consumes: [],
        may_affect: [],
        assumes: []
      }
    }.compact
  end

  def submit_impact(candidate, command_id: nil, surface: nil, actor_id: "analyzer-7")
    execute(
      Coordinator::Write::Operations::ExecuteSubmitCandidateImpactSurface,
      impact_input(candidate, command_id:, surface:, actor_id:)
    )
  end

  def release(candidate, command_id: nil)
    input = candidate.fetch(:input)
    reservation = candidate.fetch(:reservation)
    execute(Coordinator::Write::Operations::ExecuteReleaseLeaseSet, {
      command_id: command_id || "cmd-release-#{input.fetch(:candidate_id)}",
      actor: input.fetch(:actor),
      change_set_id: input.fetch(:change_set_id),
      work_item_id: input.fetch(:work_item_id),
      attempt_id: input.fetch(:attempt_id),
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |reference|
        {
          resource_id: reference.resource_id,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end
    })
  end

  def completion_input(candidate, command_id: nil, produced_outputs: [])
    input = candidate.fetch(:input)
    {
      command_id: command_id || "cmd-complete-#{input.fetch(:candidate_id)}",
      actor: input.fetch(:actor),
      change_set_id: input.fetch(:change_set_id),
      work_item_id: input.fetch(:work_item_id),
      attempt_id: input.fetch(:attempt_id),
      candidate_id: input.fetch(:candidate_id),
      produced_outputs:
    }
  end

  def complete(candidate, command_id: nil, produced_outputs: [], release: true)
    release(candidate) if release
    input = completion_input(candidate, command_id:, produced_outputs:)
    completion = execute(Coordinator::Write::Operations::ExecuteCompleteWorkItem, input)
    candidate.merge(completion_input: input, work_item_completion: completion)
  end

  def input(prefix:, ids:, reservation:, path:, agent_id:, candidate_id:, command_id:, head_commit_oid:)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      candidate_id:,
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: REPOSITORY_ID,
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid:,
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
        files: [ manifest_file(path) ]
      }
    }
  end

  def manifest_file(path)
    {
      status: "modified",
      old_path: path,
      new_path: path,
      old_blob_oid: "c" * 40,
      new_blob_oid: "d" * 40,
      old_mode: "100644",
      new_mode: "100644"
    }
  end

  def build_context_for(path)
    {
      collector_version: "build-context-v1",
      inputs: [ { kind: "public_contract", path:, blob_oid: "d" * 40 } ],
      environment: [ { name: "RUBY_VERSION", value: RUBY_VERSION } ],
      dependency_graph_digest: "sha256:#{'e' * 64}"
    }
  end

  def seed_attempt(ids:, agent_id:)
    RepositoryScenario.register(event_store:)
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "seed-create-#{ids.fetch(:change_set_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id),
      goal: "Coordinate Candidate checkpoints",
      acceptance_criteria: [ "Candidate evidence remains attributable" ]
    })
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "seed-create-#{ids.fetch(:work_item_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      repository_id: REPOSITORY_ID,
      goal: "Produce one Candidate",
      acceptance_criteria: [ "The Candidate is checkpointed" ]
    })
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "seed-activate-#{ids.fetch(:change_set_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id)
    })
    activation = event_store.read(
      streams.change_set(ids.fetch(:change_set_id)),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "seed-acquire-#{ids.fetch(:attempt_id)}",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [ { repository_id: REPOSITORY_ID, commit_oid: "a" * 40 } ]
    })
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def candidate_events(candidate_id)
    event_store.read(
      streams.candidate(candidate_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          CandidateSubmitted
          CandidateChangeManifestCaptured
          CandidateBuildContextCaptured
          CandidateImpactSurfaceDerived
        ],
        maximum_count: 4,
        direction: :asc
      )
    )
  end

  def attachment_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateAttachedToAttempt" ],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def event_store
    Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    Coordinator::Write::StreamFactory.new
  end
end
