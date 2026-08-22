# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteExpandWriteSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically acquires only new resources and records the resulting write-set size" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: [ "app/a.rb" ]
      ).value!.data
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 2, 0)) do
      operation.call(
        expand_input(
          command_id: "cmd-expand-a",
          work_item_id: "W-LSE-A",
          attempt_id: "A-LSE-A",
          agent_id: "agent-a",
          lease_set_id: reservation.lease_set_id,
          paths: [ "app/./a.rb", "app/b.rb" ]
        )
      )
    end

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to be_a(Coordinator::Write::CommandReceiptData::LeaseSetExpansion)
    expect(completion.data.to_h).to include(
      lease_set_id: reservation.lease_set_id,
      resource_count: 2,
      expanded_at: "2026-08-22T10:02:00.000000Z",
      expires_at: reservation.expires_at
    )
    expect(completion.data.added_resources.map(&:resource_path)).to eq([ "app/b.rb" ])
    expect(attempt_events("A-LSE-A").map(&:type)).to eq(
      [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved", "WriteSetExpanded" ]
    )
    expect(lease_events("app/a.rb").length).to eq(1)
    expect(lease_events("app/b.rb").sole.data).to include(
      "lease_set_id" => reservation.lease_set_id,
      "expires_at" => reservation.expires_at,
      "fencing_token" => 1
    )
    expect(command_events("cmd-expand-a").map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "replays an exact normalized expansion and rejects changed command reuse" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: [ "app/a.rb" ]
    ).value!.data
    input = expand_input(
      command_id: "cmd-expand-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      lease_set_id: reservation.lease_set_id,
      paths: [ "app/b.rb" ]
    )

    original = operation.call(input)
    original_event_ids = expansion_event_ids("A-LSE-A", "app/b.rb", "cmd-expand-a")
    replay = operation.call(input.merge(resources: [ { kind: "file", path: "app/tmp/../b.rb" } ]))
    changed = operation.call(input.merge(resources: [ { kind: "file", path: "app/c.rb" } ]))

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(changed.failure.code).to eq(:command_id_reused)
    expect(expansion_event_ids("A-LSE-A", "app/b.rb", "cmd-expand-a")).to eq(original_event_ids)
    expect(lease_events("app/c.rb")).to be_empty
  end

  it "returns zero-fact no-set, stale-set, unchanged, and evidence denials" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    no_set = operation.call(
      expand_input(
        command_id: "cmd-no-set",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        lease_set_id: "01919191-9191-7191-8191-919191919191",
        paths: [ "app/b.rb" ]
      )
    )
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: [ "app/a.rb" ]
    ).value!.data
    base = expand_input(
      command_id: "cmd-expand",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      lease_set_id: reservation.lease_set_id,
      paths: [ "app/a.rb" ]
    )
    stale_set = operation.call(base.merge(command_id: "cmd-stale", lease_set_id: "02919191-9191-7191-8191-919191919191"))
    unchanged = operation.call(base.merge(command_id: "cmd-unchanged"))
    evidence = operation.call(
      base.merge(
        command_id: "cmd-evidence",
        resources: [ { kind: "file", path: "app/a.rb", base_blob_oid: "b" * 40 } ]
      )
    )

    expect(no_set.failure.code).to eq(:write_set_not_reserved)
    expect(stale_set.failure.code).to eq(:lease_set_mismatch)
    expect(unchanged.failure.code).to eq(:write_set_unchanged)
    expect(evidence.failure.code).to eq(:resource_evidence_conflict)
    expect(%w[cmd-no-set cmd-stale cmd-unchanged cmd-evidence].flat_map { command_events(_1) }).to be_empty
    expect(attempt_events("A-LSE-A").none? { _1.type == "WriteSetExpanded" }).to be(true)
  end

  it "acquires none of a mixed addition when one resource is busy" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    reservation_a = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: [ "a.rb" ]
    ).value!.data
    reserve(
      command_id: "cmd-reserve-b",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B",
      agent_id: "agent-b",
      paths: [ "shared.rb" ]
    ).value!

    result = operation.call(
      expand_input(
        command_id: "cmd-expand-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        lease_set_id: reservation_a.lease_set_id,
        paths: [ "free.rb", "shared.rb" ]
      )
    )

    expect(result.failure.code).to eq(:lease_busy)
    expect(lease_events("free.rb")).to be_empty
    expect(command_events("cmd-expand-a")).to be_empty
    expect(attempt_events("A-LSE-A").none? { _1.type == "WriteSetExpanded" }).to be(true)
  end

  it "rejects expansion exactly at the common expiry without writing facts" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
        command_id: "cmd-reserve-a",
        actor: { kind: "agent", id: "agent-a" },
        change_set_id: "CS-LSE",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        repository_id: "billing",
        base_commit_oid: "a" * 40,
        resources: [ { kind: "file", path: "a.rb" } ],
        lease_duration_seconds: 30
      ).value!.data
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) do
      operation.call(
        expand_input(
          command_id: "cmd-expired",
          work_item_id: "W-LSE-A",
          attempt_id: "A-LSE-A",
          agent_id: "agent-a",
          lease_set_id: reservation.lease_set_id,
          paths: [ "b.rb" ]
        )
      )
    end

    expect(result.failure.code).to eq(:lease_set_expired)
    expect(result.failure.details).to include(expires_at: reservation.expires_at)
    expect(lease_events("b.rb")).to be_empty
    expect(command_events("cmd-expired")).to be_empty
  end

  it "rejects a resulting set larger than 32 before acquiring additions" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: 31.times.map { "existing-#{_1}.rb" }
    ).value!.data

    result = operation.call(
      expand_input(
        command_id: "cmd-over-bound",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        lease_set_id: reservation.lease_set_id,
        paths: [ "new-a.rb", "new-b.rb" ]
      )
    )

    expect(result.failure.code).to eq(:write_set_limit_reached)
    expect(result.failure.details).to include(current_resource_count: 31, requested_addition_count: 2)
    expect(lease_events("new-a.rb")).to be_empty
    expect(lease_events("new-b.rb")).to be_empty
    expect(command_events("cmd-over-bound")).to be_empty
  end

  it "serializes competing Attempts that add the same resource so exactly one wins" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    reservations = [
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: [ "a.rb" ]
      ).value!.data,
      reserve(
        command_id: "cmd-reserve-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        agent_id: "agent-b",
        paths: [ "b.rb" ]
      ).value!.data
    ]
    inputs = [
      expand_input(
        command_id: "cmd-expand-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        lease_set_id: reservations.first.lease_set_id,
        paths: [ "shared.rb" ]
      ),
      expand_input(
        command_id: "cmd-expand-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        agent_id: "agent-b",
        lease_set_id: reservations.last.lease_set_id,
        paths: [ "shared.rb" ]
      )
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:lease_busy)
    expect(lease_events("shared.rb").length).to eq(1)
    expect(%w[cmd-expand-a cmd-expand-b].sum { command_events(_1).length }).to eq(1)
  end

  it "serializes disjoint expansions of one Attempt and retains both additions" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: [ "a.rb" ]
    ).value!.data
    inputs = %w[b.rb c.rb].each_with_index.map do |path, index|
      expand_input(
        command_id: "cmd-expand-#{index}",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        lease_set_id: reservation.lease_set_id,
        paths: [ path ]
      )
    end

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(results.map { _1.value!.data.resource_count }.sort).to eq([ 2, 3 ])
    state = Coordinator::Write::Domain::Attempts::State.reduce(
      attempt_events("A-LSE-A").map do |event|
        Coordinator::Write::EventSchemaRegistry.new.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    )
    expect(state.lease_resources.map(&:resource_path).sort).to eq(%w[a.rb b.rb c.rb])
  end

  private

  def expand_input(command_id:, work_item_id:, attempt_id:, agent_id:, lease_set_id:, paths:)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      lease_set_id:,
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: paths.map { { kind: "file", path: _1 } }
    }
  end

  def reserve(command_id:, work_item_id:, attempt_id:, agent_id:, paths:)
    Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: paths.map { { kind: "file", path: _1 } },
      lease_duration_seconds: 900
    )
  end

  def seed_active_attempts(attempts)
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
        repository_id: "billing",
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
        base_snapshots: [ { repository_id: "billing", commit_oid: "a" * 40 } ]
      ).value!
    end
  end

  def lease_events(path)
    resource = normalizer.call(
      repository_id: "billing",
      kind: "file",
      path:,
      base_blob_oid: nil
    ).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceLeaseAcquired" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def attempt_events(attempt_id)
    event_store.read(streams.attempt(attempt_id), Coordinator::Write::EventQueries::ATTEMPT_FOR_WRITE_SET_EXPANSION)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def expansion_event_ids(attempt_id, path, command_id)
    lease_events(path).map(&:id) +
      attempt_events(attempt_id).select { _1.type == "WriteSetExpanded" }.map(&:id) +
      command_events(command_id).map(&:id)
  end
end
