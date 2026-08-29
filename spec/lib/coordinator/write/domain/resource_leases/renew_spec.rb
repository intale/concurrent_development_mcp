# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Renew do
  subject(:renew) { described_class.new }

  let(:resource) { ResourceLeaseExamples.resource }
  let(:reference) { ResourceLeaseExamples.reference(resource:) }
  let(:attempt_state) do
    ResourceLeaseExamples.active_attempt_state(
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      lease_resources: [ reference ],
      lease_expires_at: ResourceLeaseExamples::EXPIRES_AT
    )
  end
  let(:observation) do
    Coordinator::Write::CurrentLeaseObservationV2.new(
      reference:,
      state: ResourceLeaseExamples.lease_state(resource:, reference:)
    )
  end
  let(:command) do
    Coordinator::Write::Commands::RenewLeaseSet.new(
      command_id: "cmd-renew",
      actor: ResourceLeaseExamples.actor,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      leases: [
        Coordinator::Write::LeaseRenewalReferenceV2.new(
          resource_id: resource.resource_id,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        )
      ],
      lease_duration_seconds: 900
    )
  end

  it "Given an exact current set, when renewing, then retains UUID membership and fencing" do
    result = renew.call(
      attempt_state:,
      current_observations: [ observation ],
      command:,
      renewed_at: "2026-08-22T10:05:00.000000Z",
      expires_at: "2026-08-22T10:20:00.000000Z"
    )

    expect(result).to be_success
    renewal, set = result.value!.events
    expect(renewal).to be_a(Coordinator::Write::Events::ResourceLeaseRenewedV2)
    expect(renewal.to_h).to include(resource_id: resource.resource_id, fencing_token: 1)
    expect(set).to be_a(Coordinator::Write::Events::WriteSetRenewedV2)
    expect(set.resources).to eq([ reference ])
  end

  it "Given a stale fence or non-extending deadline, when renewing, then emits no facts" do
    successor = ResourceLeaseExamples.reference(resource:, fencing_token: 2)
    stale = observation.new(
      state: ResourceLeaseExamples.lease_state(resource:, reference: successor, fencing_token: 2)
    )
    stale_result = renew.call(
      attempt_state:,
      current_observations: [ stale ],
      command:,
      renewed_at: "2026-08-22T10:05:00.000000Z",
      expires_at: "2026-08-22T10:20:00.000000Z"
    )
    unchanged = renew.call(
      attempt_state:,
      current_observations: [ observation ],
      command:,
      renewed_at: "2026-08-22T10:05:00.000000Z",
      expires_at: ResourceLeaseExamples::EXPIRES_AT
    )

    expect(stale_result.failure.code).to eq(:lease_set_not_current)
    expect(unchanged.failure.code).to eq(:lease_deadline_not_extended)
  end
end
