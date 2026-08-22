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

  it "folds the latest acquisition and advances fencing monotonically" do
    state = described_class.reduce([ acquired ])

    expect(state).to be_active_at("2026-08-22T10:14:59.999999Z")
    expect(state).not_to be_active_at("2026-08-22T10:15:00.000000Z")
    expect(state.next_fencing_token).to eq(5)
  end
end
