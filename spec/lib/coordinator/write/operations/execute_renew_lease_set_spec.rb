# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRenewLeaseSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically renews the complete set while preserving membership, lease IDs, and fencing tokens" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: %w[app/a.rb app/b.rb],
        duration: 600
      ).value!.data
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 5, 0)) do
      operation.call(renewal_input(command_id: "cmd-renew-a", reservation:))
    end

    expect(result).to be_success
    renewal = result.value!.data
    expect(renewal).to be_a(Coordinator::Write::CommandReceiptData::LeaseSetRenewal)
    expect(renewal.to_h).to include(
      lease_set_id: reservation.lease_set_id,
      resource_count: 2,
      renewed_at: "2026-08-22T10:05:00.000000Z",
      previous_expires_at: "2026-08-22T10:10:00.000000Z",
      expires_at: "2026-08-22T10:20:00.000000Z"
    )
    expect(renewal.resources).to eq(reservation.resources)
    expect(attempt_events("A-LSE-A").map(&:type)).to eq(
      [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved", "WriteSetRenewed" ]
    )
    %w[app/a.rb app/b.rb].each do |path|
      acquired, renewed = lease_events(path)
      expect([ renewed.data["lease_id"], renewed.data["fencing_token"] ]).to eq(
        [ acquired.data["lease_id"], acquired.data["fencing_token"] ]
      )
      expect(renewed.data).to include(
        "previous_expires_at" => reservation.expires_at,
        "expires_at" => renewal.expires_at
      )
    end
    expect(command_events("cmd-renew-a").map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "replays exact normalized input and rejects changed command reuse without duplicate renewals" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = reserve(
      command_id: "cmd-reserve-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      paths: %w[a.rb b.rb]
    ).value!.data
    input = renewal_input(command_id: "cmd-renew-a", reservation:)

    original = operation.call(input)
    replay = operation.call(input.merge(leases: input.fetch(:leases).reverse))
    changed = operation.call(input.merge(lease_duration_seconds: 1_000))

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(changed.failure.code).to eq(:command_id_reused)
    expect(%w[a.rb b.rb].flat_map { lease_events(_1) }.count { _1.type == "ResourceLeaseRenewed" }).to eq(2)
    expect(attempt_events("A-LSE-A").count { _1.type == "WriteSetRenewed" }).to eq(1)
  end

  it "returns zero-fact incomplete, stale-reference, no-extension, and expired denials" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: %w[a.rb b.rb],
        duration: 600
      ).value!.data
    end
    base = renewal_input(command_id: "cmd-renew", reservation:)

    incomplete = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 0)) do
      operation.call(base.merge(command_id: "cmd-incomplete", leases: base.fetch(:leases).first(1)))
    end
    stale = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 0)) do
      references = base.fetch(:leases).map(&:dup)
      references.first[:fencing_token] += 1
      operation.call(base.merge(command_id: "cmd-stale", leases: references))
    end
    no_extension = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 0)) do
      operation.call(base.merge(command_id: "cmd-short", lease_duration_seconds: 30))
    end
    expired = Timecop.freeze(Time.utc(2026, 8, 22, 10, 10, 0)) do
      operation.call(base.merge(command_id: "cmd-expired"))
    end

    expect(incomplete.failure.code).to eq(:lease_set_snapshot_mismatch)
    expect(stale.failure.code).to eq(:lease_reference_mismatch)
    expect(no_extension.failure.code).to eq(:lease_deadline_not_extended)
    expect(expired.failure.code).to eq(:lease_set_expired)
    expect(%w[cmd-incomplete cmd-stale cmd-short cmd-expired].flat_map { command_events(_1) }).to be_empty
    expect(%w[a.rb b.rb].flat_map { lease_events(_1) }.none? { _1.type == "ResourceLeaseRenewed" }).to be(true)
  end

  it "makes the renewed deadline authoritative for later expansion and competing reservation" do
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
        paths: [ "a.rb" ],
        duration: 600
      ).value!.data
    end
    renewal = Timecop.freeze(Time.utc(2026, 8, 22, 10, 5, 0)) do
      operation.call(renewal_input(command_id: "cmd-renew-a", reservation:)).value!.data
    end

    expansion = Timecop.freeze(Time.utc(2026, 8, 22, 10, 11, 0)) do
      Coordinator::Write::Operations::ExecuteExpandWriteSet.new(event_store:).call(
        command_id: "cmd-expand-a",
        actor: { kind: "agent", id: "agent-a" },
        change_set_id: "CS-LSE",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        lease_set_id: reservation.lease_set_id,
        repository_id: "billing",
        base_commit_oid: "a" * 40,
        resources: [ { kind: "file", path: "b.rb" } ]
      )
    end
    conflict = Timecop.freeze(Time.utc(2026, 8, 22, 10, 11, 0)) do
      reserve(
        command_id: "cmd-reserve-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        agent_id: "agent-b",
        paths: [ "a.rb" ]
      )
    end

    expect(expansion).to be_success
    expect(expansion.value!.data.expires_at).to eq(renewal.expires_at)
    expect(lease_events("b.rb").sole.data.fetch("expires_at")).to eq(renewal.expires_at)
    expect(conflict.failure.code).to eq(:lease_busy)
    expect(conflict.failure.details.fetch(:expires_at)).to eq(renewal.expires_at)
  end

  it "serializes same-set renewal so an identical deadline commits exactly once" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: %w[a.rb b.rb],
        duration: 600
      ).value!.data
    end
    inputs = %w[cmd-renew-a cmd-renew-b].map { renewal_input(command_id: _1, reservation:) }

    results = Timecop.freeze(Time.utc(2026, 8, 22, 10, 5, 0)) do
      inputs.map do |input|
        Thread.new { described_class.new(event_store:).call(input) }
      end.map(&:value)
    end

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:lease_deadline_not_extended)
    expect(attempt_events("A-LSE-A").count { _1.type == "WriteSetRenewed" }).to eq(1)
    expect(%w[a.rb b.rb].flat_map { lease_events(_1) }.count { _1.type == "ResourceLeaseRenewed" }).to eq(2)
  end

  private

  def renewal_input(command_id:, reservation:)
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
      end,
      lease_duration_seconds: 900
    }
  end

  def reserve(command_id:, work_item_id:, attempt_id:, agent_id:, paths:, duration: 900)
    Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: paths.map { { kind: "file", path: _1 } },
      lease_duration_seconds: duration
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
    resource = normalizer.call(repository_id: "billing", kind: "file", path:, base_blob_oid: nil).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceLeaseAcquired", "ResourceLeaseRenewed" ],
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
          "WriteSetRenewed"
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
