# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRenewLeaseSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically renews a complete UUID set while retaining lease IDs and fences" do
    reservation = setup_reservation
    result = operation.call(renew_input(reservation, command_id: "cmd-renew-v2"))

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to be_a(Coordinator::Write::CommandReceiptData::LeaseSetRenewal)
    expect(receipt.resources.map(&:resource_id)).to eq(reservation.receipt.resources.map(&:resource_id))
    expect(receipt.resources.map(&:lease_id)).to eq(reservation.receipt.resources.map(&:lease_id))
    expect(receipt.resources.map(&:fencing_token)).to eq([ 1, 1 ])
    expect(receipt.expires_at).to be > receipt.previous_expires_at
    expect(reservation.resource_ids.flat_map { lease_events(_1).map(&:type) }).to all(eq("ResourceLeaseRenewed").or(eq("ResourceLeaseAcquired")))
  end

  it "rejects incomplete and stale UUID fence snapshots without partial renewals" do
    reservation = setup_reservation
    leases = ResourceLeaseOperationScenario.lease_inputs(reservation.receipt)
    incomplete = operation.call(
      renew_input(reservation, command_id: "cmd-renew-incomplete").merge(leases: leases.first(1))
    )
    stale = operation.call(
      renew_input(reservation, command_id: "cmd-renew-stale").merge(
        leases: leases.map.with_index { |entry, index| index.zero? ? entry.merge(fencing_token: 2) : entry }
      )
    )

    expect(incomplete.failure.code).to eq(:lease_set_snapshot_mismatch)
    expect(stale.failure.code).to eq(:lease_reference_mismatch)
    expect(command_events("cmd-renew-incomplete")).to be_empty
    expect(command_events("cmd-renew-stale")).to be_empty
  end

  def setup_reservation
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
    ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "app/a.rb", "app/b.rb" ])
  end

  def renew_input(reservation, command_id:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.receipt.lease_set_id,
      leases: ResourceLeaseOperationScenario.lease_inputs(reservation.receipt),
      lease_duration_seconds: 900
    }
  end

  def lease_events(resource_id)
    ResourceScenario.lease_events(event_store:, resource_id:)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
