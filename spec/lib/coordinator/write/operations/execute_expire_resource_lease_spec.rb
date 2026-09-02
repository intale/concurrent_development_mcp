# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteExpireResourceLease, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  subject(:operation) { described_class.new(event_store:) }

  it "records exact UUID lease expiry and a trace-linked completion at the deadline" do
    reservation = nil
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      setup_attempt
      reservation = ResourceLeaseOperationScenario.reserve(
        event_store:,
        paths: [ "app/expiring.rb" ],
        lease_duration_seconds: 30
      )
    end
    source = lease_events(reservation.resource_ids.sole).find { _1.type == "ResourceLeaseAcquired" }
    reference = reservation.receipt.resources.sole
    command = expiry_command(reference, reservation.receipt, source:)

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) do
      operation.call(command, caused_by: source)
    end

    expect(result).to be_success
    expiration = lease_events(reference.resource_id).find { _1.type == "ResourceLeaseExpired" }
    expect(expiration.data).to include("resource_id" => reference.resource_id)
    expect(expiration).to have_attributes(causation_id: source.id, correlation_id: source.correlation_id)
  end

  it "cannot let an acquisition timer expire the same UUID lease after renewal moved its deadline" do
    reservation = nil
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      setup_attempt
      reservation = ResourceLeaseOperationScenario.reserve(
        event_store:,
        paths: [ "app/renewed.rb" ],
        lease_duration_seconds: 30
      )
    end
    source = lease_events(reservation.resource_ids.sole).find { _1.type == "ResourceLeaseAcquired" }
    reference = reservation.receipt.resources.sole
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 10)) do
      Coordinator::Write::Operations::ExecuteRenewLeaseSet.new(event_store:).call(
        command_id: "cmd-renew-before-expiry",
        actor: { kind: "agent", id: "agent-a" },
        change_set_id: "CS-LSE",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        lease_set_id: reservation.receipt.lease_set_id,
        leases: ResourceLeaseOperationScenario.lease_inputs(reservation.receipt),
        lease_duration_seconds: 60
      ).value!
    end

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) do
      operation.call(expiry_command(reference, reservation.receipt, source:), caused_by: source)
    end

    expect(result.failure.code).to eq(:lease_observation_superseded)
    expect(lease_events(reference.resource_id).none? { _1.type == "ResourceLeaseExpired" }).to be(true)
  end

  def setup_attempt
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
  end

  def expiry_command(reference, receipt, source:)
    Coordinator::Write::Commands::ExpireResourceLease.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "lease-expiry-policy-v1"),
      resource_id: reference.resource_id,
      lease_id: reference.lease_id,
      lease_set_id: receipt.lease_set_id,
      fencing_token: reference.fencing_token,
      expected_expires_at: receipt.expires_at
    )
  end

  def lease_events(resource_id)
    ResourceScenario.lease_events(event_store:, resource_id:)
  end
end
