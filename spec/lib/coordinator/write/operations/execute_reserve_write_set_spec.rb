# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteReserveWriteSet, :event_store do
  REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "resolves server-owned Resource identity before atomically writing schema-v2 leases" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    first = resolve("app/services/capture.rb")
    second = resolve("db/schema.rb")
    input = reserve_input(
      command_id: "cmd-reserve-v2",
      agent_id: "agent-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      resource_ids: [ first, second ]
    )

    result = operation.call(input)

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to be_a(Coordinator::Write::CommandReceiptData::LeaseSet)
    expect(receipt).to have_attributes(policy_version: "coordinator-resource-lease/v2")
    expect(receipt.resources.map(&:resource_id)).to contain_exactly(first, second)
    expect(receipt.resources).to all(be_a(Coordinator::Write::LeaseReferenceV2))

    [ first, second ].each do |resource_id|
      event = lease_events(resource_id).sole
      expect(event).to have_attributes(type: "ResourceLeaseAcquired", stream_revision: 0)
      expect(event.stream.stream_id).to eq(resource_id)
      expect(event.data).to include("resource_id" => resource_id, "fencing_token" => 1)
      expect(event.data).not_to have_key("resource_key_hash")
      expect(event.markers).to include("resource:#{resource_id}")
      expect(event.markers).not_to include(a_string_starting_with("resource-key-hash:"))
    end
  end

  it "leaves replay ownership to the registered Command lifecycle without duplicate facts" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    resource_id = resolve("app/replay.rb")
    input = reserve_input(
      command_id: "cmd-reserve-replay",
      agent_id: "agent-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      resource_ids: [ resource_id ]
    )

    original = operation.call(input)
    replay = operation.call(input)
    changed = operation.call(input.merge(lease_duration_seconds: 901))

    expect(original).to be_success
    expect(replay.failure.code).to eq(:write_set_already_reserved)
    expect(changed.failure.code).to eq(:write_set_already_reserved)
    expect(lease_events(resource_id).length).to eq(1)
    expect(command_events("cmd-reserve-replay")).to be_empty
  end

  it "rejects missing, cross-repository, and inactive Resources from write-side facts" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    active = resolve("app/inactive.rb")
    Coordinator::Write::Operations::ExecuteRemoveResource.new(event_store:).call(
      command_id: "cmd-remove-before-lease",
      actor: { kind: "agent", id: "agent-a" },
      resource_id: active,
      reason: "removed"
    ).value!
    missing = SecureRandom.uuid_v7

    inactive = operation.call(
      reserve_input(
        command_id: "cmd-inactive-resource",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        resource_ids: [ active ]
      )
    )
    absent = operation.call(
      reserve_input(
        command_id: "cmd-missing-resource",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        resource_ids: [ missing ]
      )
    )

    expect(inactive.failure).to have_attributes(code: :resource_not_active)
    expect(inactive.failure.details).to include(resource_id: active)
    expect(absent.failure).to have_attributes(code: :resource_not_found, details: { resource_id: missing })
    expect(command_events("cmd-inactive-resource")).to be_empty
    expect(command_events("cmd-missing-resource")).to be_empty
  end

  it "serializes two agents contending for the same Resource so only one full decision commits" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    shared = resolve("app/shared.rb")
    first = reserve_input(
      command_id: "cmd-race-a",
      agent_id: "agent-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      resource_ids: [ shared ]
    )
    second = reserve_input(
      command_id: "cmd-race-b",
      agent_id: "agent-b",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B",
      resource_ids: [ shared ]
    )

    results = [ first, second ].map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:lease_busy)
    expect(lease_events(shared).length).to eq(1)
    expect(%w[cmd-race-a cmd-race-b].flat_map { command_events(_1) }).to be_empty
  end

  it "blocks directory descendants across distinct UUIDs but does not treat a file prefix as an ancestor" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    directory = resolve("app/models", kind: "directory")
    child = resolve("app/models/user.rb")
    parent_file = resolve("app/services")
    child_file = resolve("app/services/capture.rb")

    operation.call(
      reserve_input(
        command_id: "cmd-directory-owner",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        resource_ids: [ directory ]
      )
    ).value!
    blocked = operation.call(
      reserve_input(
        command_id: "cmd-directory-child",
        agent_id: "agent-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        resource_ids: [ child ]
      )
    )

    expect(blocked.failure).to have_attributes(code: :lease_busy)
    expect(blocked.failure.details).to include(resource_id: child)

    release_receipt(operation.call(
      reserve_input(
        command_id: "cmd-file-prefix-owner",
        agent_id: "agent-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        resource_ids: [ parent_file, child_file ]
      )
    ))
    expect(lease_events(parent_file).length).to eq(1)
    expect(lease_events(child_file).length).to eq(1)
  end

  def release_receipt(result)
    expect(result).to be_success
    result.value!
  end

  def resolve(path, kind: "file")
    ResourceScenario.resolve(event_store:, repository_id: REPOSITORY_ID, kind:, path:)
  end

  def reserve_input(command_id:, agent_id:, work_item_id:, attempt_id:, resource_ids:)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      repository_id: REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: resource_ids.map { { resource_id: _1 } },
      lease_duration_seconds: 900
    }
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
        repository_id: REPOSITORY_ID,
        goal: "Implement #{work_item_id}",
        acceptance_criteria: [ "The work is verifiable" ]
      ).value!
    end
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE"
    ).value!
    activation = event_store.read(streams.change_set("CS-LSE"), Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION)
      .find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    attempts.each do |work_item_id, attempt_id, agent_id|
      Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
        command_id: "seed-acquire-#{attempt_id}",
        actor: { kind: "agent", id: agent_id },
        change_set_id: "CS-LSE",
        work_item_id:,
        attempt_id:,
        base_snapshots: [ { repository_id: REPOSITORY_ID, commit_oid: "a" * 40 } ]
      ).value!
    end
  end

  def lease_events(resource_id)
    ResourceScenario.lease_events(event_store:, resource_id:)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end
