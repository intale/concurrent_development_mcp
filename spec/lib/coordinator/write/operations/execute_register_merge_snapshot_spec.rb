# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRegisterMergeSnapshot, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:operation) { described_class.new(event_store:) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "registers exact ordered Candidate evidence and replays the same command" do
    candidates = seed_candidates("merge-register")
    input = registration_input("merge-register", candidates:)

    first = operation.call(input)
    replay = operation.call(input)

    expect(first).to be_success
    expect(replay).to be_success
    expect(replay.value!).to eq(first.value!)
    snapshot = snapshot_events("MS-merge-register").sole
    registry = commit_events(input.fetch(:merge_commit_oid)).sole
    expect(snapshot.data.fetch("ordered_candidates").map { _1.fetch("candidate_id") }).to eq(
      candidates.map { _1.fetch(:candidate_id) }
    )
    expect(snapshot.data.fetch("evidence_status")).to eq("attributed_unverified")
    expect(registry.data.fetch("snapshot_event").fetch("event_id")).to eq(snapshot.id)
    expect(snapshot.correlation_id).to eq(registry.correlation_id)
    expect(snapshot.correlation_id).to eq(command_events(input.fetch(:command_id)).sole.correlation_id)
  end

  it "denies missing, mismatched, and competing immutable evidence without partial facts" do
    candidates = seed_candidates("merge-denials")
    missing = registration_input(
      "merge-missing",
      candidates: [ { candidate_id: "CAN-absent", head_commit_oid: "f" * 40 } ]
    )
    mismatch = registration_input(
      "merge-mismatch",
      candidates: [ candidates.first.merge(head_commit_oid: "f" * 40) ]
    )
    accepted = registration_input("merge-accepted", candidates:)
    competing = registration_input(
      "merge-competing",
      candidates:,
      merge_commit_oid: accepted.fetch(:merge_commit_oid)
    )

    expect(operation.call(missing).failure.code).to eq(:candidate_not_found)
    expect(operation.call(mismatch).failure.code).to eq(:candidate_head_mismatch)
    expect(operation.call(accepted)).to be_success
    expect(operation.call(competing).failure.code).to eq(:merge_commit_already_registered)
    expect(snapshot_events("MS-merge-missing")).to be_empty
    expect(snapshot_events("MS-merge-mismatch")).to be_empty
    expect(snapshot_events("MS-merge-competing")).to be_empty
  end

  it "serializes competing registrations for one merge commit with one complete winner" do
    candidates = seed_candidates("merge-race")
    inputs = [
      registration_input("merge-race-a", candidates:),
      registration_input("merge-race-b", candidates:)
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:merge_commit_already_registered)
    expect(commit_events(inputs.first.fetch(:merge_commit_oid)).length).to eq(1)
    expect(
      inputs.sum { snapshot_events(_1.fetch(:merge_snapshot_id)).length }
    ).to eq(1)
  end

  def seed_candidates(prefix)
    [ [ "one", "b" * 40 ], [ "two", "e" * 40 ] ].map do |suffix, head|
      prepared = CandidateScenario.prepare(
        prefix: "#{prefix}-#{suffix}",
        path: "lib/#{prefix}-#{suffix}.rb"
      )
      input = prepared.fetch(:input).merge(head_commit_oid: head)
      result = Coordinator::Write::Operations::ExecuteSubmitCandidate.new(event_store:).call(input)
      expect(result).to be_success
      { candidate_id: input.fetch(:candidate_id), head_commit_oid: head }
    end
  end

  def registration_input(prefix, candidates:, merge_commit_oid: "9" * 40)
    {
      command_id: "cmd-#{prefix}",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: "MS-#{prefix}",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      target_branch: "main",
      target_base_commit_oid: "a" * 40,
      ordered_candidates: candidates,
      merge_commit_oid:,
      producer: { name: "git-merge", version: "2.47.0" },
      run_id: "run-#{prefix}",
      produced_at: "2026-08-24T15:30:00.000001Z"
    }
  end

  def snapshot_events(snapshot_id)
    event_store.read(streams.merge_snapshot(snapshot_id), Coordinator::Write::EventQueries::MERGE_SNAPSHOT_REGISTRATION)
  end

  def commit_events(oid)
    identity = Coordinator::Write::MergeSnapshots::CommitIdentityBuilder.new.call(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      object_format: "sha1",
      merge_commit_oid: oid
    )
    event_store.read(
      streams.merge_snapshot_commit(identity.registry_id),
      Coordinator::Write::EventQueries::MERGE_SNAPSHOT_COMMIT_REGISTRATION
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
