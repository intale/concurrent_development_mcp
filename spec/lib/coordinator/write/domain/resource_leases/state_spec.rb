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

  it "temporarily reads a schema-v1 lifecycle for in-flight pre-cutover cleanup" do
    legacy = Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
      lease_id: reference.lease_id,
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      resource_key: "legacy-resource",
      resource_key_hash: "sha256:#{'f' * 64}",
      resource_kind: "file",
      resource_path: "legacy.rb",
      policy_version: "coordinator-resource-key/v3",
      mode: "exclusive",
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      repository_id: ResourceLeaseExamples::REPOSITORY_ID,
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      base_blob_oid: nil,
      fencing_token: 1,
      acquired_at: ResourceLeaseExamples::ACQUIRED_AT,
      expires_at: ResourceLeaseExamples::EXPIRES_AT
    )

    state = described_class.reduce([ legacy ])
    expect(state.identity).to eq("sha256:#{'f' * 64}")
    expect(state.resource_id).to be_nil
  end

  it "restores a schema-v1 boundary snapshot into the expanded lease state" do
    legacy = Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
      lease_id: reference.lease_id,
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      resource_key: "legacy-resource",
      resource_key_hash: "sha256:#{'f' * 64}",
      resource_kind: "directory",
      resource_path: "lib/coordinator/write",
      policy_version: "coordinator-resource-key/v3",
      mode: "exclusive",
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      repository_id: ResourceLeaseExamples::REPOSITORY_ID,
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      base_blob_oid: nil,
      fencing_token: 3,
      acquired_at: ResourceLeaseExamples::ACQUIRED_AT,
      expires_at: ResourceLeaseExamples::EXPIRES_AT
    )
    active = described_class.reduce([ legacy ])

    restored = Coordinator::Write::Events::ResourceBoundaryEpochRolledV1::ActiveLeaseV1
      .from_state(active)
      .to_state

    expect(restored).to have_attributes(
      identity: "sha256:#{'f' * 64}",
      resource_id: nil,
      resource_path: "lib/coordinator/write",
      fencing_token: 3
    )
  end
end
