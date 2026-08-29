# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::State do
  let(:resource) { ResourceLeaseExamples.resource }
  let(:reference) { ResourceLeaseExamples.reference(resource:) }
  let(:acquisition) { ResourceLeaseExamples.acquisition(resource:, reference:) }

  it "reduces UUID lifecycle facts in stream order and keeps the monotonic fence" do
    renewal = Coordinator::Write::Events::ResourceLeaseRenewedV2.new(
      **acquisition.to_h.except(:acquired_at),
      renewed_at: "2026-08-22T10:05:00.000000Z",
      previous_expires_at: ResourceLeaseExamples::EXPIRES_AT,
      expires_at: "2026-08-22T10:20:00.000000Z"
    )
    release = Coordinator::Write::Events::ResourceLeaseReleasedV2.new(
      **acquisition.to_h.except(:expires_at),
      acquired_at: ResourceLeaseExamples::ACQUIRED_AT,
      previous_expires_at: "2026-08-22T10:20:00.000000Z",
      released_at: "2026-08-22T10:06:00.000000Z"
    )

    active = described_class.reduce([ acquisition, renewal ])
    closed = described_class.reduce([ acquisition, renewal, release ])

    expect(active).to have_attributes(
      identity: resource.resource_id,
      resource_id: resource.resource_id,
      fencing_token: 1,
      renewed_at: "2026-08-22T10:05:00.000000Z"
    )
    expect(active.active_at?("2026-08-22T10:19:00.000000Z")).to be(true)
    expect(closed.active_at?("2026-08-22T10:07:00.000000Z")).to be(false)
    expect(closed.next_fencing_token).to eq(2)
  end

  it "restores a UUID boundary snapshot into the lease state" do
    active = described_class.reduce([ acquisition ])

    restored = Coordinator::Write::Events::ResourceBoundaryEpochRolledV2::ActiveLeaseV2
      .from_state(active)
      .to_state

    expect(restored).to have_attributes(
      identity: resource.resource_id,
      resource_id: resource.resource_id,
      resource_path: resource.path,
      fencing_token: 1
    )
  end
end
