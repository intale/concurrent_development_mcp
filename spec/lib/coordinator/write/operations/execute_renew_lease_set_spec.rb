# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRenewLeaseSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "renews every active intention without recording a set snapshot" do
    reservation = setup_reservation

    result = operation.call(renew_input(reservation, command_id: "cmd-renew-intentions"))

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt.resources.map(&:lease_id)).to eq(reservation.receipt.resources.map(&:lease_id))
    expect(receipt.resources.map(&:fencing_token)).to eq([ 1, 1 ])
    expect(receipt.expires_at).to be > receipt.previous_expires_at
    receipt.resources.each do |reference|
      events = read_intention(reference.lease_id)
      expect(events.map(&:type)).to eq(
        [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionRenewed" ]
      )
      renewal = events.last
      expect(renewal.data.keys).to contain_exactly(
        "intention_id", "resource_id", "fencing_token", "expires_at"
      )
      expect(renewal.data).to include(
        "intention_id" => reference.lease_id,
        "resource_id" => reference.resource_id,
        "fencing_token" => reference.fencing_token
      )
    end
    expect(result.value!.emitted_events.map(&:type)).not_to include("WriteSetRenewed")
  end

  it "rejects incomplete and stale member observations without partial renewal" do
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

    expect(incomplete.failure).to have_attributes(code: :lease_set_snapshot_mismatch)
    expect(stale.failure).to have_attributes(code: :lease_reference_mismatch)
    reservation.receipt.resources.each do |reference|
      expect(read_intention(reference.lease_id).map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    end
  end

  it "returns a no-change result when the requested deadline would not extend the intentions" do
    reservation = nil
    Timecop.freeze(Time.utc(2026, 9, 1, 10, 0, 0)) do
      reservation = setup_reservation
    end

    result = Timecop.freeze(Time.utc(2026, 9, 1, 10, 0, 10)) do
      operation.call(
        renew_input(reservation, command_id: "cmd-renew-shorter").merge(
          lease_duration_seconds: 30
        )
      )
    end

    expect(result).to be_success
    expect(result.value!.emitted_events).to be_empty
    reservation.receipt.resources.each do |reference|
      expect(read_intention(reference.lease_id).map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    end
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

  def read_intention(intention_id)
    event_store.read_grouped(
      streams.resource_work_intention(intention_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_STATE
    ).reverse
  end
end
