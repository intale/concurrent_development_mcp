# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteReleaseLeaseSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically releases an exact elapsed set while preserving membership, lease IDs, and fencing tokens" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: %w[app/a.rb app/b.rb],
        duration: 60
      ).value!.data
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 2, 0)) do
      operation.call(release_input(command_id: "cmd-release-a", reservation:))
    end

    expect(result).to be_success
    release = result.value!.data
    expect(release).to be_a(Coordinator::Write::CommandReceiptData::LeaseSetRelease)
    expect(release.to_h).to include(
      lease_set_id: reservation.lease_set_id,
      resource_count: 2,
      previous_expires_at: "2026-08-22T10:01:00.000000Z",
      released_at: "2026-08-22T10:02:00.000000Z"
    )
    expect(release.resources).to eq(reservation.resources)
    expect(attempt_events("A-LSE-A").map(&:type)).to eq(
      [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved", "WriteSetReleased" ]
    )
    %w[app/a.rb app/b.rb].each do |path|
      acquired, released = lease_events(path)
      expect([ released.data["lease_id"], released.data["fencing_token"] ]).to eq(
        [ acquired.data["lease_id"], acquired.data["fencing_token"] ]
      )
      expect(released.data).to include(
        "previous_expires_at" => reservation.expires_at,
        "released_at" => release.released_at
      )
      expect(released.metadata.fetch("policy_version")).to eq("coordinator-resource-key/v2")
      expect(released.markers).to include(
        "scope:#{RepositoryScenario::DEFAULT_SCOPE}",
        "repository:#{repository_id}"
      )
      expect(released.markers.grep(/\Acompound:resource-identity:v1:sha256:/).length).to eq(1)
      expect(released.markers.grep(/\Acompound:scoped-repository:v1:sha256:/).length).to eq(1)
    end
    expect(command_events("cmd-release-a").map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "replays the command and lets a new exact command reference the original release without duplicate facts" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: %w[a.rb b.rb]
    ).value!.data
    input = release_input(command_id: "cmd-release-a", reservation:)

    original = operation.call(input)
    replay = operation.call(input.merge(leases: input.fetch(:leases).reverse))
    another = operation.call(input.merge(command_id: "cmd-release-b"))
    changed = operation.call(
      input.merge(leases: input.fetch(:leases).map.with_index do |reference, index|
        index.zero? ? reference.merge(fencing_token: reference.fetch(:fencing_token) + 1) : reference
      end)
    )

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(another).to be_success
    expect(another.value!.data).to eq(original.value!.data)
    expect(changed.failure.code).to eq(:command_id_reused)
    release_events = %w[a.rb b.rb].flat_map { lease_events(_1) }.select { _1.type == "ResourceLeaseReleased" }
    expect(release_events.length).to eq(2)
    expect(attempt_events("A-LSE-A").count { _1.type == "WriteSetReleased" }).to eq(1)
    original_references = command_events("cmd-release-a").sole.data.fetch("emitted_events").pluck("event_id")
    another_references = command_events("cmd-release-b").sole.data.fetch("emitted_events").pluck("event_id")
    expect(another_references).to eq(original_references)
  end

  it "returns zero-fact incomplete and stale-reference denials" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: %w[a.rb b.rb]
    ).value!.data
    base = release_input(command_id: "cmd-release", reservation:)

    incomplete = operation.call(
      base.merge(command_id: "cmd-incomplete", leases: base.fetch(:leases).first(1))
    )
    references = base.fetch(:leases).map(&:dup)
    references.first[:fencing_token] += 1
    stale = operation.call(base.merge(command_id: "cmd-stale", leases: references))

    expect(incomplete.failure.code).to eq(:lease_set_snapshot_mismatch)
    expect(stale.failure.code).to eq(:lease_reference_mismatch)
    expect(%w[cmd-incomplete cmd-stale].flat_map { command_events(_1) }).to be_empty
    expect(%w[a.rb b.rb].flat_map { lease_events(_1) }.none? { _1.type == "ResourceLeaseReleased" }).to be(true)
  end

  it "cannot release any old member after one elapsed resource is acquired by a successor" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: %w[a.rb b.rb],
        duration: 60
      ).value!.data
    end
    successor = Timecop.freeze(Time.utc(2026, 8, 22, 10, 2, 0)) do
      reserve(
        command_id: "cmd-reserve-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        agent_id: "agent-b",
        paths: [ "b.rb" ]
      )
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 2, 1)) do
      operation.call(release_input(command_id: "cmd-release-a", reservation:))
    end

    expect(successor).to be_success
    expect(result.failure.code).to eq(:lease_set_not_current)
    expect(lease_events("a.rb").none? { _1.type == "ResourceLeaseReleased" }).to be(true)
    expect(lease_events("b.rb").none? { _1.type == "ResourceLeaseReleased" }).to be(true)
    expect(command_events("cmd-release-a")).to be_empty
  end

  it "makes released resources immediately acquirable while denying later expansion and renewal" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: [ "a.rb" ]
    ).value!.data
    operation.call(release_input(command_id: "cmd-release-a", reservation:)).value!

    successor = reserve(
      command_id: "cmd-reserve-b",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B",
      agent_id: "agent-b",
      paths: [ "a.rb" ]
    )
    expansion = Coordinator::Write::Operations::ExecuteExpandWriteSet.new(event_store:).call(
      command_id: "cmd-expand-a",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.lease_set_id,
      repository_id:,
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path: "b.rb" } ]
    )
    renewal = Coordinator::Write::Operations::ExecuteRenewLeaseSet.new(event_store:).call(
      release_input(command_id: "cmd-renew-a", reservation:).merge(lease_duration_seconds: 900)
    )

    expect(successor).to be_success
    acquired = lease_events("a.rb").select { _1.type == "ResourceLeaseAcquired" }
    expect(acquired.map { _1.data.fetch("fencing_token") }).to eq([ 1, 2 ])
    expect(expansion.failure.code).to eq(:write_set_released)
    expect(renewal.failure.code).to eq(:write_set_released)
  end

  it "serializes same-set release so both commands succeed but release facts exist once" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: %w[a.rb b.rb]
    ).value!.data
    inputs = %w[cmd-release-a cmd-release-b].map { release_input(command_id: _1, reservation:) }

    results = Timecop.freeze(Time.utc(2026, 8, 22, 10, 5, 0)) do
      inputs.map do |input|
        Thread.new { described_class.new(event_store:).call(input) }
      end.map(&:value)
    end

    expect(results).to all(be_success)
    expect(results.map { _1.value!.data }.uniq.length).to eq(1)
    expect(attempt_events("A-LSE-A").count { _1.type == "WriteSetReleased" }).to eq(1)
    expect(%w[a.rb b.rb].flat_map { lease_events(_1) }.count { _1.type == "ResourceLeaseReleased" }).to eq(2)
    expect(inputs.flat_map { command_events(_1.fetch(:command_id)) }.length).to eq(2)
  end

  private

  def release_input(command_id:, reservation:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |reference|
        {
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end
    }
  end

  def reserve(command_id:, work_item_id:, attempt_id:, agent_id:, paths:, duration: 900)
    Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      repository_id:,
      base_commit_oid: "a" * 40,
      resources: paths.map { { kind: "file", path: _1 } },
      lease_duration_seconds: duration
    )
  end

  def seed_active_attempts(attempts)
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE",
      goal: "Coordinate resource leases",
      acceptance_criteria: [ "Overlapping agents cannot both write" ]
    ).value!
    attempts.each do |work_item_id, _attempt_id, _agent_id|
      Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
        command_id: "seed-create-#{work_item_id}",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-LSE",
        work_item_id:,
        repository_id:,
        goal: "Implement #{work_item_id}",
        acceptance_criteria: [ "The work is verifiable" ]
      ).value!
    end
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE"
    ).value!
    activation = event_store.read(
      streams.change_set("CS-LSE"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    attempts.each do |work_item_id, attempt_id, agent_id|
      Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
        command_id: "seed-acquire-#{attempt_id}",
        actor: { kind: "agent", id: agent_id },
        change_set_id: "CS-LSE",
        work_item_id:,
        attempt_id:,
        base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
      ).value!
    end
  end

  def lease_events(path)
    resource = normalizer.call(
      repository_id:,
      kind: "file",
      path:,
      base_blob_oid: nil,
      scope: RepositoryScenario::DEFAULT_SCOPE
    ).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceLeaseAcquired", "ResourceLeaseRenewed", "ResourceLeaseReleased" ],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def attempt_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [
          "AttemptAuthorized",
          "AttemptStarted",
          "WriteSetReserved",
          "WriteSetExpanded",
          "WriteSetRenewed",
          "WriteSetReleased"
        ],
        maximum_count: 50,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
