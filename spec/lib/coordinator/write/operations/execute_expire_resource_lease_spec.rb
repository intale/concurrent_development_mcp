# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteExpireResourceLease, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "records expiry as one fact on the exact intention stream at its deadline" do
    reservation = nil
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      setup_attempt
      reservation = ResourceLeaseOperationScenario.reserve(
        event_store:,
        paths: [ "app/expiring.rb" ],
        lease_duration_seconds: 30
      )
    end
    reference = reservation.receipt.resources.sole
    source = read_intention(reference.lease_id).sole

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) do
      operation.call(expiry_command(reference, reservation.receipt), caused_by: source)
    end

    expect(result).to be_success
    expiration = read_intention(reference.lease_id).last
    expect(expiration.type).to eq("ResourceWorkIntentionExpired")
    expect(expiration.data.keys).to contain_exactly(
      "intention_id", "resource_id", "fencing_token", "expires_at"
    )
    expect(expiration.data).to include(
      "intention_id" => reference.lease_id,
      "resource_id" => reference.resource_id,
      "expires_at" => reservation.receipt.expires_at
    )
    expect(expiration).to have_attributes(causation_id: source.id, correlation_id: source.correlation_id)
  end

  it "treats an obsolete deadline after renewal as a no-change decision" do
    reservation = nil
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      setup_attempt
      reservation = ResourceLeaseOperationScenario.reserve(
        event_store:,
        paths: [ "app/renewed.rb" ],
        lease_duration_seconds: 30
      )
    end
    reference = reservation.receipt.resources.sole
    source = read_intention(reference.lease_id).sole
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
      operation.call(expiry_command(reference, reservation.receipt), caused_by: source)
    end

    expect(result).to be_success
    expect(result.value!.emitted_events).to be_empty
    expect(read_intention(reference.lease_id).map(&:type)).to eq(
      [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionRenewed" ]
    )
  end

  def setup_attempt
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
  end

  def expiry_command(reference, receipt)
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

  def read_intention(intention_id)
    event_store.read_grouped(
      streams.resource_work_intention(intention_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_STATE
    ).reverse
  end
end
