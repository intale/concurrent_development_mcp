# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteExpireResourceLease, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically records an exact elapsed lease and its deterministic completion" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    source = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: [ "app/a.rb" ],
        duration: 60
      ).value!
      lease_events("app/a.rb").sole
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 0)) do
      operation.call(expiry_command(source), caused_by: source)
    end

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to be_a(Coordinator::Write::CommandReceiptData::ResourceLeaseExpiry)
    expect(receipt.to_h).to include(
      resource_key_hash: source.data.fetch("resource_key_hash"),
      lease_id: source.data.fetch("lease_id"),
      fencing_token: 1,
      expires_at: "2026-08-22T10:01:00.000000Z",
      expired_at: "2026-08-22T10:01:00.000000Z"
    )
    expiration = lease_events("app/a.rb").last
    expect(expiration.type).to eq("ResourceLeaseExpired")
    expect(expiration.causation_id).to eq(source.id)
    expect(expiration.correlation_id).to eq(source.correlation_id)
    expect(command_events(source.id).map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "returns a zero-fact early decision and can succeed when the same timer reaches its deadline" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    source = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: [ "a.rb" ],
        duration: 60
      ).value!
      lease_events("a.rb").sole
    end

    early = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 59)) do
      operation.call(expiry_command(source), caused_by: source)
    end
    on_time = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 0)) do
      operation.call(expiry_command(source), caused_by: source)
    end

    expect(early.failure.code).to eq(:lease_deadline_not_reached)
    expect(on_time).to be_success
    expect(lease_events("a.rb").map(&:type)).to eq([ "ResourceLeaseAcquired", "ResourceLeaseExpired" ])
    expect(command_events(source.id).length).to eq(1)
  end

  it "lets renewal supersede the old timer and expires only the renewed observation" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: [ "a.rb" ],
        duration: 60
      ).value!.data
    end
    acquisition = lease_events("a.rb").sole
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) do
      Coordinator::Write::Operations::ExecuteRenewLeaseSet.new(event_store:).call(
        renewal_input(command_id: "cmd-renew-a", reservation:, duration: 120)
      ).value!
    end
    renewal = lease_events("a.rb").last

    old_result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 0)) do
      operation.call(expiry_command(acquisition), caused_by: acquisition)
    end
    renewed_result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 2, 30)) do
      operation.call(expiry_command(renewal), caused_by: renewal)
    end

    expect(old_result.failure.code).to eq(:lease_observation_superseded)
    expect(renewed_result).to be_success
    expect(lease_events("a.rb").map(&:type)).to eq(
      [ "ResourceLeaseAcquired", "ResourceLeaseRenewed", "ResourceLeaseExpired" ]
    )
    expect(command_events(acquisition.id)).to be_empty
    expect(command_events(renewal.id).length).to eq(1)
  end

  it "cannot let an old timer expire a successor acquired after the elapsed deadline" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    source = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: [ "a.rb" ],
        duration: 60
      ).value!
      lease_events("a.rb").sole
    end
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 1)) do
      reserve(
        command_id: "cmd-reserve-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        agent_id: "agent-b",
        paths: [ "a.rb" ]
      ).value!
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 2)) do
      operation.call(expiry_command(source), caused_by: source)
    end

    expect(result.failure.code).to eq(:lease_observation_superseded)
    events = lease_events("a.rb")
    expect(events.map(&:type)).to eq([ "ResourceLeaseAcquired", "ResourceLeaseAcquired" ])
    expect(events.map { _1.data.fetch("fencing_token") }).to eq([ 1, 2 ])
    expect(command_events(source.id)).to be_empty
  end

  it "serializes duplicate timer execution into one fact and one completion" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    source = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(
        command_id: "cmd-reserve-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        paths: [ "a.rb" ],
        duration: 60
      ).value!
      lease_events("a.rb").sole
    end

    results = Timecop.freeze(Time.utc(2026, 8, 22, 10, 1, 0)) do
      2.times.map do
        Thread.new do
          described_class.new(event_store:).call(expiry_command(source), caused_by: source)
        end
      end.map(&:value)
    end

    expect(results).to all(be_success)
    expect(results.map { _1.value!.to_h }.uniq.length).to eq(1)
    expect(lease_events("a.rb").count { _1.type == "ResourceLeaseExpired" }).to eq(1)
    expect(command_events(source.id).length).to eq(1)
  end

  private

  def expiry_command(source)
    data = source.data
    Coordinator::Write::Commands::ExpireResourceLease.new(
      command_id: source.id,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "lease-expiry-policy-v1"),
      resource_key_hash: data.fetch("resource_key_hash"),
      lease_id: data.fetch("lease_id"),
      lease_set_id: data.fetch("lease_set_id"),
      fencing_token: data.fetch("fencing_token"),
      expected_expires_at: data.fetch("expires_at")
    )
  end

  def renewal_input(command_id:, reservation:, duration:)
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
      lease_duration_seconds: duration
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
        event_types: [
          "ResourceLeaseAcquired",
          "ResourceLeaseRenewed",
          "ResourceLeaseReleased",
          "ResourceLeaseExpired"
        ],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
