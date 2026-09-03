# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteReleaseLeaseSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically releases the complete UUID set without duplicate release facts" do
    reservation = setup_reservation
    input = release_input(reservation, command_id: "cmd-release-v2")

    first = operation.call(input)
    replay = operation.call(input)

    expect(first).to be_success
    expect(replay).to be_success
    expect(replay.value!.data).to eq(first.value!.data)
    expect(replay.value!.emitted_events).to eq(first.value!.emitted_events)
    receipt = first.value!.data
    expect(receipt).to be_a(Coordinator::Write::CommandReceiptData::LeaseSetRelease)
    expect(receipt.resources.map(&:resource_id)).to eq(reservation.receipt.resources.map(&:resource_id))
    expect(reservation.resource_ids.flat_map { lease_events(_1) }.count { _1.type == "ResourceLeaseReleased" }).to eq(2)
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "makes released Resources immediately acquirable by another agent with greater fences" do
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ], [ "W-LSE-B", "A-LSE-B", "agent-b" ] ]
    )
    reservation = ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "app/shared.rb" ])
    operation.call(release_input(reservation, command_id: "cmd-release-owner")).value!

    successor = Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "cmd-successor-reserve",
      actor: { kind: "agent", id: "agent-b" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: reservation.resource_ids.map { { resource_id: _1 } },
      lease_duration_seconds: 900
    )

    expect(successor).to be_success
    acquisitions = event_store.read(
      Coordinator::Write::StreamFactory.new.resource_lease(reservation.resource_ids.sole),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceLeaseAcquired" ],
        maximum_count: 10,
        direction: :asc
      )
    )
    expect(acquisitions.map { _1.data.fetch("fencing_token") }).to eq([ 1, 2 ])
  end

  it "rejects incomplete UUID membership without releasing any member" do
    reservation = setup_reservation
    input = release_input(reservation, command_id: "cmd-release-incomplete")
    result = operation.call(input.merge(leases: input.fetch(:leases).first(1)))

    expect(result.failure.code).to eq(:lease_set_snapshot_mismatch)
    expect(reservation.resource_ids.flat_map { lease_events(_1) }.none? { _1.type == "ResourceLeaseReleased" }).to be(true)
    expect(command_events("cmd-release-incomplete")).to be_empty
  end

  def setup_reservation
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
    ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "app/a.rb", "app/b.rb" ])
  end

  def release_input(reservation, command_id:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.receipt.lease_set_id,
      leases: ResourceLeaseOperationScenario.lease_inputs(reservation.receipt)
    }
  end

  def lease_events(resource_id)
    ResourceScenario.lease_events(event_store:, resource_id:)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end
