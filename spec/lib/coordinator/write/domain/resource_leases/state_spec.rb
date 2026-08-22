# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::State do
  let(:acquired) do
    Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
      lease_id: "01919191-9191-7191-8191-919191919191",
      lease_set_id: "02919191-9191-7191-8191-919191919191",
      resource_key: "repo:billing:file:app/models/user.rb",
      resource_key_hash: "sha256:#{'a' * 64}",
      resource_kind: "file",
      resource_path: "app/models/user.rb",
      policy_version: "coordinator-resource-key/v1",
      mode: "exclusive",
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      repository_id: "billing",
      object_format: "sha1",
      base_commit_oid: "b" * 40,
      base_blob_oid: nil,
      fencing_token: 4,
      acquired_at: "2026-08-22T10:00:00.000000Z",
      expires_at: "2026-08-22T10:15:00.000000Z"
    )
  end
  let(:renewed) do
    Coordinator::Write::Events::ResourceLeaseRenewedV1.new(
      acquired.to_h.except(:acquired_at, :expires_at).merge(
        renewed_at: "2026-08-22T10:05:00.000000Z",
        previous_expires_at: acquired.expires_at,
        expires_at: "2026-08-22T10:20:00.000000Z"
      )
    )
  end
  let(:released) do
    Coordinator::Write::Events::ResourceLeaseReleasedV1.new(
      acquired.to_h.except(:expires_at).merge(
        previous_expires_at: acquired.expires_at,
        released_at: "2026-08-22T10:07:00.000000Z"
      )
    )
  end
  let(:expired) do
    Coordinator::Write::Events::ResourceLeaseExpiredV1.new(
      acquired.to_h.merge(
        renewed_at: nil,
        expired_at: acquired.expires_at
      )
    )
  end

  it "folds the latest acquisition and advances fencing monotonically" do
    state = described_class.reduce([ acquired ])

    expect(state).to be_active_at("2026-08-22T10:14:59.999999Z")
    expect(state).not_to be_active_at("2026-08-22T10:15:00.000000Z")
    expect(state.next_fencing_token).to eq(5)
  end

  it "folds renewal after acquisition while preserving lease and fencing identity" do
    state = described_class.reduce([ acquired, renewed ])

    expect(state.to_h).to include(
      lease_id: acquired.lease_id,
      lease_set_id: acquired.lease_set_id,
      fencing_token: 4,
      acquired_at: acquired.acquired_at,
      renewed_at: renewed.renewed_at,
      expires_at: renewed.expires_at
    )
    expect(state.next_fencing_token).to eq(5)
    expect(state).to be_active_at("2026-08-22T10:19:59.999999Z")
  end

  it "folds release as inactive while preserving the token for the next acquisition" do
    state = described_class.reduce([ acquired, released ])

    expect(state).not_to be_active_at("2026-08-22T10:07:00.000001Z")
    expect(state.to_h).to include(
      lease_id: acquired.lease_id,
      fencing_token: 4,
      expires_at: acquired.expires_at,
      released_at: released.released_at
    )
    expect(state.next_fencing_token).to eq(5)
  end

  it "folds explicit expiry as inactive audit evidence while preserving fencing" do
    state = described_class.reduce([ acquired, expired ])

    expect(state).not_to be_active_at("2026-08-22T10:14:00.000000Z")
    expect(state.to_h).to include(
      lease_id: acquired.lease_id,
      fencing_token: 4,
      expires_at: acquired.expires_at,
      expired_at: acquired.expires_at
    )
    expect(state.next_fencing_token).to eq(5)
  end
end
