# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Expire do
  subject(:expire) { described_class.new }

  let(:deadline) { "2026-08-22T10:01:00.000000Z" }
  let(:acquired) do
    Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
      lease_id: "01919191-9191-7191-8191-919191919191",
      lease_set_id: "02919191-9191-7191-8191-919191919191",
      resource_key: "repo:billing:file:app/a.rb",
      resource_key_hash: "sha256:#{'a' * 64}",
      resource_kind: "file",
      resource_path: "app/a.rb",
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
      expires_at: deadline
    )
  end
  let(:state) { Coordinator::Write::Domain::ResourceLeases::State.reduce([ acquired ]) }
  let(:command) do
    Coordinator::Write::Commands::ExpireResourceLease.new(
      command_id: "01919191-9191-7191-8191-919191919199",
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "lease-expiry-policy-v1"),
      resource_key_hash: acquired.resource_key_hash,
      lease_id: acquired.lease_id,
      lease_set_id: acquired.lease_set_id,
      fencing_token: acquired.fencing_token,
      expected_expires_at: deadline
    )
  end

  it "Given the exact current lease at its deadline, when the policy evaluates it, then emits expiry" do
    result = expire.call(state:, command:, expired_at: deadline)

    expect(result).to be_success
    write = result.value!.writes.sole
    expect(write.stream).to eq(Coordinator::Write::StreamFactory.new.resource_lease(acquired.resource_key_hash))
    expect(write.event).to be_a(Coordinator::Write::Events::ResourceLeaseExpiredV1)
    expect(write.event.to_h).to include(
      lease_id: acquired.lease_id,
      lease_set_id: acquired.lease_set_id,
      fencing_token: 4,
      expires_at: deadline,
      expired_at: deadline
    )
  end

  it "Given the deadline is in the future, when the policy evaluates it, then emits no facts" do
    result = expire.call(
      state:,
      command:,
      expired_at: "2026-08-22T10:00:59.999999Z"
    )

    expect(result.failure.code).to eq(:lease_deadline_not_reached)
    expect(result.failure.details).to include(expected_expires_at: deadline)
  end

  it "Given renewal superseded the observed deadline, when the old timer runs, then emits no facts" do
    renewed = Coordinator::Write::Events::ResourceLeaseRenewedV1.new(
      acquired.to_h.except(:acquired_at, :expires_at).merge(
        renewed_at: "2026-08-22T10:00:30.000000Z",
        previous_expires_at: deadline,
        expires_at: "2026-08-22T10:02:30.000000Z"
      )
    )

    result = expire.call(
      state: state.apply(renewed),
      command:,
      expired_at: deadline
    )

    expect(result.failure.code).to eq(:lease_observation_superseded)
    expect(result.failure.details).to include(current_expires_at: renewed.expires_at)
  end

  it "Given an explicit expiry already exists, when the same observation is re-decided, then emits no facts" do
    expiration = expire.call(state:, command:, expired_at: deadline).value!.events.sole

    result = expire.call(
      state: state.apply(expiration),
      command:,
      expired_at: "2026-08-22T10:01:01.000000Z"
    )

    expect(result.failure.code).to eq(:lease_already_expired)
    expect(result.failure.details).to include(current_expired_at: deadline)
  end
end
