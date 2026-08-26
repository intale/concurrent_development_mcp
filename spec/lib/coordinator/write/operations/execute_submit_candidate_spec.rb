# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteSubmitCandidate, :event_store do
  CANDIDATE_REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID

  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "atomically persists immutable submission, evidence, head ownership, Attempt attachment, and completion" do
    seed_attempts([ [ "W-CAN-A", "A-CAN-A", "agent-a" ] ])
    reservation = reserve("W-CAN-A", "A-CAN-A", "agent-a", "lib/a.rb")

    result = operation.call(candidate_input(reservation:, build_context: build_context("lib/a.rb")))

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to be_a(Coordinator::Write::CommandReceiptData::CandidateSubmission)
    expect(completion.data).to have_attributes(
      candidate_id: "CAN-A",
      evidence_status: "attributed_unverified",
      head_commit_oid: "b" * 40
    )
    expect(completion.emitted_events.map(&:type)).to eq([
      "CandidateSubmitted",
      "CandidateChangeManifestCaptured",
      "CandidateBuildContextCaptured",
      "CandidateHeadRegistered",
      "CandidateAttachedToAttempt"
    ])
    expect(candidate_events("CAN-A").map(&:type)).to eq([
      "CandidateSubmitted",
      "CandidateChangeManifestCaptured",
      "CandidateBuildContextCaptured"
    ])
    expect(attempt_candidate_events("A-CAN-A").map(&:type)).to eq([ "CandidateAttachedToAttempt" ])
    expect(command_events("cmd-CAN-A").map(&:type)).to eq([ "CommandCompleted" ])

    submission = candidate_events("CAN-A").first
    registration = head_events(CANDIDATE_REPOSITORY_ID, "b" * 40).sole
    expect(registration.data.fetch("candidate_event")).to eq(
      "event_id" => submission.id,
      "type" => "CandidateSubmitted",
      "stream_context" => "DevelopmentIntegration",
      "stream_name" => "Candidate",
      "stream_id" => "CAN-A",
      "stream_revision" => 0
    )
    expect(registration.markers).to include(
      "scope:#{RepositoryScenario::DEFAULT_SCOPE}",
      "repository:#{CANDIDATE_REPOSITORY_ID}",
      "object-format:sha1",
      "head-commit-oid:#{"b" * 40}"
    )
    expect(registration.markers.grep(/\Acompound:candidate-head-identity:v1:sha256:/).length).to eq(1)
    expect(registration.metadata).not_to have_key("correlation_id")
  end

  it "replays normalized input exactly and rejects changed command reuse" do
    seed_attempts([ [ "W-CAN-A", "A-CAN-A", "agent-a" ] ])
    reservation = reserve("W-CAN-A", "A-CAN-A", "agent-a", "lib/a.rb")
    input = candidate_input(reservation:)
    original = operation.call(input)
    event_ids = all_candidate_submission_event_ids(input)

    replay = operation.call(
      input.merge(
        change_manifest: input.fetch(:change_manifest).merge(
          files: [ manifest_file("lib/./a.rb") ]
        )
      )
    )
    changed = operation.call(input.merge(checkpoint_kind: "handoff"))

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(changed.failure.code).to eq(:command_id_reused)
    expect(all_candidate_submission_event_ids(input)).to eq(event_ids)
  end

  it "denies stale authority and manifest escape without appending target facts" do
    seed_attempts([ [ "W-CAN-A", "A-CAN-A", "agent-a" ] ])
    reservation = reserve("W-CAN-A", "A-CAN-A", "agent-a", "lib/a.rb")
    input = candidate_input(reservation:)
    stale = operation.call(
      input.merge(
        command_id: "cmd-stale",
        leases: input.fetch(:leases).map { _1.merge(fencing_token: _1.fetch(:fencing_token) + 1) }
      )
    )
    escaped = operation.call(
      input.merge(
        command_id: "cmd-escape",
        candidate_id: "CAN-ESCAPE",
        change_manifest: { collector_version: "git-evidence-v1", files: [ manifest_file("lib/other.rb") ] }
      )
    )
    base_mismatch_file = manifest_file("lib/a.rb").merge(
      old_blob_oid: "e" * 40,
      new_blob_oid: "f" * 40
    )
    base_mismatch = operation.call(
      input.merge(
        command_id: "cmd-base-mismatch",
        candidate_id: "CAN-BASE-MISMATCH",
        change_manifest: { collector_version: "git-evidence-v1", files: [ base_mismatch_file ] }
      )
    )

    expect(stale.failure.code).to eq(:lease_observations_mismatch)
    expect(escaped.failure.code).to eq(:actual_write_set_not_authorized)
    expect(base_mismatch.failure.code).to eq(:manifest_base_evidence_mismatch)
    expect(candidate_events("CAN-A")).to be_empty
    expect(candidate_events("CAN-ESCAPE")).to be_empty
    expect(candidate_events("CAN-BASE-MISMATCH")).to be_empty
    expect(command_events("cmd-stale")).to be_empty
    expect(command_events("cmd-escape")).to be_empty
    expect(command_events("cmd-base-mismatch")).to be_empty
  end

  it "keeps an existing Candidate immutable and leaves a second head unregistered" do
    seed_attempts(
      [
        [ "W-CAN-A", "A-CAN-A", "agent-a" ],
        [ "W-CAN-B", "A-CAN-B", "agent-b" ]
      ]
    )
    first_reservation = reserve("W-CAN-A", "A-CAN-A", "agent-a", "lib/a.rb")
    second_reservation = reserve("W-CAN-B", "A-CAN-B", "agent-b", "lib/b.rb")
    first = operation.call(candidate_input(reservation: first_reservation))
    second = operation.call(
      candidate_input(
        reservation: second_reservation,
        command_id: "cmd-candidate-reuse",
        work_item_id: "W-CAN-B",
        attempt_id: "A-CAN-B",
        agent_id: "agent-b",
        path: "lib/b.rb",
        head_commit_oid: "e" * 40
      )
    )

    expect(first).to be_success
    expect(second.failure.code).to eq(:candidate_id_already_used)
    expect(candidate_events("CAN-A").count { _1.type == "CandidateSubmitted" }).to eq(1)
    expect(head_events(CANDIDATE_REPOSITORY_ID, "e" * 40)).to be_empty
    expect(command_events("cmd-candidate-reuse")).to be_empty
  end

  it "serializes competing Candidate IDs for one repository head so exactly one owns it" do
    seed_attempts(
      [
        [ "W-CAN-A", "A-CAN-A", "agent-a" ],
        [ "W-CAN-B", "A-CAN-B", "agent-b" ]
      ]
    )
    reservations = [
      reserve("W-CAN-A", "A-CAN-A", "agent-a", "lib/a.rb"),
      reserve("W-CAN-B", "A-CAN-B", "agent-b", "lib/b.rb")
    ]
    inputs = [
      candidate_input(reservation: reservations.fetch(0)),
      candidate_input(
        reservation: reservations.fetch(1),
        command_id: "cmd-CAN-B",
        candidate_id: "CAN-B",
        work_item_id: "W-CAN-B",
        attempt_id: "A-CAN-B",
        agent_id: "agent-b",
        path: "lib/b.rb"
      )
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:candidate_head_already_registered)
    expect(head_events(CANDIDATE_REPOSITORY_ID, "b" * 40).length).to eq(1)
    expect(%w[CAN-A CAN-B].sum { candidate_events(_1).count { |event| event.type == "CandidateSubmitted" } }).to eq(1)
  end

  it "allows disjoint Candidate, head, Attempt, and lease boundaries to commit concurrently" do
    seed_attempts(
      [
        [ "W-CAN-A", "A-CAN-A", "agent-a" ],
        [ "W-CAN-B", "A-CAN-B", "agent-b" ]
      ]
    )
    inputs = [
      candidate_input(reservation: reserve("W-CAN-A", "A-CAN-A", "agent-a", "lib/a.rb")),
      candidate_input(
        reservation: reserve("W-CAN-B", "A-CAN-B", "agent-b", "lib/b.rb"),
        command_id: "cmd-CAN-B",
        candidate_id: "CAN-B",
        work_item_id: "W-CAN-B",
        attempt_id: "A-CAN-B",
        agent_id: "agent-b",
        path: "lib/b.rb",
        head_commit_oid: "e" * 40
      )
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(candidate_events("CAN-A").count { _1.type == "CandidateSubmitted" }).to eq(1)
    expect(candidate_events("CAN-B").count { _1.type == "CandidateSubmitted" }).to eq(1)
    expect(head_events(CANDIDATE_REPOSITORY_ID, "b" * 40).length).to eq(1)
    expect(head_events(CANDIDATE_REPOSITORY_ID, "e" * 40).length).to eq(1)
  end

  it "serializes a lease release race without a partial Candidate" do
    seed_attempts([ [ "W-CAN-A", "A-CAN-A", "agent-a" ] ])
    reservation = reserve("W-CAN-A", "A-CAN-A", "agent-a", "lib/a.rb")
    release_input = {
      command_id: "cmd-release-CAN-A",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-CAN",
      work_item_id: "W-CAN-A",
      attempt_id: "A-CAN-A",
      lease_set_id: reservation.data.lease_set_id,
      leases: reservation.data.resources.map do |reference|
        {
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end
    }

    candidate_thread = Thread.new { described_class.new(event_store:).call(candidate_input(reservation:)) }
    release_thread = Thread.new do
      Coordinator::Write::Operations::ExecuteReleaseLeaseSet.new(event_store:).call(release_input)
    end
    candidate_result, release_result = [ candidate_thread, release_thread ].map(&:value)

    expect(release_result).to be_success
    if candidate_result.success?
      expect(candidate_events("CAN-A").count { _1.type == "CandidateSubmitted" }).to eq(1)
      expect(command_events("cmd-CAN-A").length).to eq(1)
    else
      expect([ :lease_set_released, :lease_not_active ]).to include(candidate_result.failure.code)
      expect(candidate_events("CAN-A")).to be_empty
      expect(command_events("cmd-CAN-A")).to be_empty
    end
  end

  def candidate_input(
    reservation:,
    command_id: "cmd-CAN-A",
    candidate_id: "CAN-A",
    work_item_id: "W-CAN-A",
    attempt_id: "A-CAN-A",
    agent_id: "agent-a",
    path: "lib/a.rb",
    head_commit_oid: "b" * 40,
    build_context: nil
  )
    data = reservation.data
    input = {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      candidate_id:,
      change_set_id: "CS-CAN",
      work_item_id:,
      attempt_id:,
      repository_id: CANDIDATE_REPOSITORY_ID,
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid:,
      checkpoint_kind: "final",
      lease_set_id: data.lease_set_id,
      leases: data.resources.map do |reference|
        {
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end,
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [ manifest_file(path) ]
      }
    }
    input[:build_context] = build_context if build_context
    input
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

  def build_context(path)
    {
      collector_version: "build-context-v1",
      inputs: [ { kind: "public_contract", path:, blob_oid: "d" * 40 } ],
      environment: [ { name: "RUBY_VERSION", value: RUBY_VERSION } ],
      dependency_graph_digest: "sha256:#{"e" * 64}"
    }
  end

  def seed_attempts(attempts)
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-CS-CAN",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-CAN",
      goal: "Coordinate Candidate submissions",
      acceptance_criteria: [ "A repository head has one Candidate owner" ]
    ).value!

    attempts.each do |work_item_id, _attempt_id, _agent_id|
      Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
        command_id: "seed-create-#{work_item_id}",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-CAN",
        work_item_id:,
        repository_id: CANDIDATE_REPOSITORY_ID,
        goal: "Implement #{work_item_id}",
        acceptance_criteria: [ "The Candidate is attributable" ]
      ).value!
    end

    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-CS-CAN",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-CAN"
    ).value!
    activation = event_store.read(
      streams.change_set("CS-CAN"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)

    attempts.each do |work_item_id, attempt_id, agent_id|
      Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
        command_id: "seed-acquire-#{attempt_id}",
        actor: { kind: "agent", id: agent_id },
        change_set_id: "CS-CAN",
        work_item_id:,
        attempt_id:,
        base_snapshots: [ { repository_id: CANDIDATE_REPOSITORY_ID, commit_oid: "a" * 40 } ]
      ).value!
    end
  end

  def reserve(work_item_id, attempt_id, agent_id, path)
    result = Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "seed-reserve-#{attempt_id}",
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-CAN",
      work_item_id:,
      attempt_id:,
      repository_id: CANDIDATE_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path:, base_blob_oid: "c" * 40 } ],
      lease_duration_seconds: 900
    )
    result.value!
  end

  def candidate_events(candidate_id)
    event_store.read(
      streams.candidate(candidate_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [
          "CandidateSubmitted",
          "CandidateChangeManifestCaptured",
          "CandidateBuildContextCaptured"
        ],
        maximum_count: 3,
        direction: :asc
      )
    )
  end

  def attempt_candidate_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateAttachedToAttempt" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def head_events(repository_id, head_commit_oid)
    identity = Coordinator::Write::Candidates::HeadIdentityBuilder.new.call(
      repository_id:,
      object_format: "sha1",
      head_commit_oid:
    )
    event_store.read(
      streams.candidate_head(identity.registry_id),
      Coordinator::Write::EventQueries::CANDIDATE_HEAD_REGISTRATION
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def all_candidate_submission_event_ids(input)
    candidate_events(input.fetch(:candidate_id)).map(&:id) +
      head_events(input.fetch(:repository_id), input.fetch(:head_commit_oid)).map(&:id) +
      attempt_candidate_events(input.fetch(:attempt_id)).map(&:id) +
      command_events(input.fetch(:command_id)).map(&:id)
  end
end
