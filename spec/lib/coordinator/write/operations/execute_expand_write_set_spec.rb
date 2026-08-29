# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteExpandWriteSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically appends UUID lease membership while preserving the original deadline" do
    reservation = setup_reservation
    added = resolve("app/models/b.rb")

    result = operation.call(expand_input(reservation, command_id: "cmd-expand-v2", resource_ids: [ added ]))

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to be_a(Coordinator::Write::CommandReceiptData::LeaseSetExpansion)
    expect(receipt.added_resources.sole).to be_a(Coordinator::Write::LeaseReferenceV2)
    expect(receipt.added_resources.sole.resource_id).to eq(added)
    expect(receipt.expires_at).to eq(reservation.receipt.expires_at)
    expect(lease_events(added).sole.data).not_to have_key("resource_key_hash")
  end

  it "replays exact input and rejects an unchanged set without new facts" do
    reservation = setup_reservation
    input = expand_input(
      reservation,
      command_id: "cmd-expand-existing",
      resource_ids: reservation.resource_ids
    )

    unchanged = operation.call(input)
    replay = operation.call(input)

    expect(unchanged.failure.code).to eq(:write_set_unchanged)
    expect(replay.failure.code).to eq(:write_set_unchanged)
    expect(command_events("cmd-expand-existing")).to be_empty
  end

  it "acquires none of a mixed UUID addition when another agent owns one member" do
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ], [ "W-LSE-B", "A-LSE-B", "agent-b" ] ]
    )
    owner = ResourceLeaseOperationScenario.reserve(
      event_store:,
      paths: [ "app/a.rb" ],
      command_id: "seed-reserve-a"
    )
    busy = ResourceLeaseOperationScenario.reserve(
      event_store:,
      paths: [ "app/busy.rb" ],
      command_id: "seed-reserve-b",
      agent_id: "agent-b",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B"
    )
    free = resolve("app/free.rb")

    result = operation.call(
      expand_input(owner, command_id: "cmd-expand-busy", resource_ids: [ free, busy.resource_ids.sole ])
    )

    expect(result.failure).to have_attributes(code: :lease_busy)
    expect(result.failure.details).to include(resource_id: busy.resource_ids.sole)
    expect(lease_events(free)).to be_empty
    expect(command_events("cmd-expand-busy")).to be_empty
  end

  it "rejects an inactive Resource before changing Attempt membership" do
    reservation = setup_reservation
    inactive = resolve("app/removed.rb")
    Coordinator::Write::Operations::ExecuteRemoveResource.new(event_store:).call(
      command_id: "cmd-remove-expanded-resource",
      actor: { kind: "agent", id: "agent-a" },
      resource_id: inactive,
      reason: "removed"
    ).value!

    result = operation.call(
      expand_input(reservation, command_id: "cmd-expand-inactive", resource_ids: [ inactive ])
    )

    expect(result.failure).to have_attributes(code: :resource_not_active)
    expect(result.failure.details).to include(resource_id: inactive)
    expect(command_events("cmd-expand-inactive")).to be_empty
  end

  def setup_reservation
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
    ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "app/models/a.rb" ])
  end

  def expand_input(reservation, command_id:, resource_ids:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.receipt.lease_set_id,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: resource_ids.map { { resource_id: _1 } }
    }
  end

  def resolve(path)
    ResourceScenario.resolve(
      event_store:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      kind: "file",
      path:
    )
  end

  def lease_events(resource_id)
    ResourceScenario.lease_events(event_store:, resource_id:)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
