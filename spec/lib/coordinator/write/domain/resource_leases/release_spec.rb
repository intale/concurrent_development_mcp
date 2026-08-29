# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Release do
  subject(:release) { described_class.new }

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
    Coordinator::Write::Commands::ReleaseLeaseSet.new(
      command_id: "cmd-release",
      actor: ResourceLeaseExamples.actor,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      leases: [
        Coordinator::Write::LeaseReleaseReferenceV2.new(
          resource_id: resource.resource_id,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        )
      ]
    )
  end

  it "Given an exact current set, when releasing, then closes UUID leases without changing fences" do
    decision = release.call(
      attempt_state:,
      current_observations: [ observation ],
      command:,
      released_at: "2026-08-22T10:05:00.000000Z"
    ).value!

    expect(decision).to be_release
    released, set = decision.plan.events
    expect(released).to be_a(Coordinator::Write::Events::ResourceLeaseReleasedV2)
    expect(released.to_h).to include(resource_id: resource.resource_id, fencing_token: 1)
    expect(set).to be_a(Coordinator::Write::Events::WriteSetReleasedV2)
  end

  it "Given a stale submitted fence, when releasing, then emits no facts" do
    stale_command = command.new(
      leases: [ command.leases.sole.new(fencing_token: 2) ]
    )
    stale = release.call(
      attempt_state:,
      current_observations: [ observation ],
      command: stale_command,
      released_at: "2026-08-22T10:05:00.000000Z"
    )

    expect(stale.failure.code).to eq(:lease_reference_mismatch)
  end

  it "Given a durable release fact on the Attempt, when replaying, then selects the stored result" do
    released_attempt = attempt_state.new(lease_released_at: "2026-08-22T10:05:00.000000Z")
    decision = release.call(
      attempt_state: released_attempt,
      current_observations: [ observation ],
      command:,
      released_at: "2026-08-22T10:06:00.000000Z"
    ).value!

    expect(decision.kind).to eq("already_released")
    expect(decision.plan).to be_nil
  end
end
