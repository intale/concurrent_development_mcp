# frozen_string_literal: true

RSpec.describe Coordinator::Processes::LeaseExpiryCommandBuilder do
  subject(:builder) { described_class.new }

  let(:source_event_id) { "0198c000-0000-7000-8000-000000000001" }
  let(:source_reference) do
    Coordinator::Write::EventReference.new(
      event_id: source_event_id,
      type: "ResourceLeaseAcquired",
      stream_context: "DevelopmentCoordination",
      stream_name: "ResourceLease",
      stream_id: "sha256:#{'f' * 64}",
      stream_revision: 4
    )
  end
  let(:source_payload) do
    Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
      lease_id: "0198c000-0000-7000-8000-000000000002",
      lease_set_id: "0198c000-0000-7000-8000-000000000003",
      resource_key: "scope:project:test:repo:billing:file:app/a.rb",
      resource_key_hash: "sha256:#{'f' * 64}",
      resource_kind: "file",
      resource_path: "app/a.rb",
      policy_version: "coordinator-resource-key/v3",
      mode: "exclusive",
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      agent_id: "agent-a",
      repository_id: "billing",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      base_blob_oid: "b" * 40,
      fencing_token: 2,
      acquired_at: "2026-08-27T08:00:00.000000Z",
      expires_at: "2026-08-27T08:01:00.000000Z"
    )
  end
  let(:source) do
    Coordinator::Processes::LeaseExpirySource.new(
      event: PgEventstore::Event.new(id: source_event_id, type: "ResourceLeaseAcquired"),
      reference: source_reference,
      payload: source_payload
    )
  end

  it "derives one deterministic system-owned command identity from the parent event" do
    command = builder.call(source)

    expect(command.command_id).to eq("internal:lease-expiry:v1:#{source_event_id}")
    expect(command.actor.to_h).to eq(kind: "system", id: "lease-expiry-policy-v1")
    expect(command.to_h).to include(
      resource_key_hash: source_payload.resource_key_hash,
      lease_id: source_payload.lease_id,
      lease_set_id: source_payload.lease_set_id,
      fencing_token: source_payload.fencing_token,
      expected_expires_at: source_payload.expires_at
    )
    expect(builder.call(source)).to eq(command)
  end
end
