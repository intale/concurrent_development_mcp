# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Expire do
  subject(:expire) { described_class.new }

  let(:resource) { ResourceLeaseExamples.resource }
  let(:reference) { ResourceLeaseExamples.reference(resource:) }
  let(:state) { ResourceLeaseExamples.lease_state(resource:, reference:) }
  let(:command) do
    Coordinator::Write::Commands::ExpireResourceLease.new(
      command_id: "internal:lease-expiry:v1:test",
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "lease-expiry-policy-v1"),
      resource_id: resource.resource_id,
      lease_id: reference.lease_id,
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      fencing_token: reference.fencing_token,
      expected_expires_at: ResourceLeaseExamples::EXPIRES_AT
    )
  end

  it "Given the exact UUID lease at its deadline, when expiring, then emits one schema-v2 fact" do
    result = expire.call(state:, command:, expired_at: ResourceLeaseExamples::EXPIRES_AT)

    expect(result).to be_success
    event = result.value!.events.sole
    expect(event).to be_a(Coordinator::Write::Events::ResourceLeaseExpiredV2)
    expect(event.to_h).to include(resource_id: resource.resource_id, lease_id: reference.lease_id)
  end

  it "Given an early timer or superseded fence, when expiring, then emits no facts" do
    early = expire.call(state:, command:, expired_at: "2026-08-22T10:14:59.000000Z")
    stale = expire.call(state:, command: command.new(fencing_token: 2), expired_at: ResourceLeaseExamples::EXPIRES_AT)

    expect(early.failure.code).to eq(:lease_deadline_not_reached)
    expect(stale.failure.code).to eq(:lease_observation_superseded)
  end
end
