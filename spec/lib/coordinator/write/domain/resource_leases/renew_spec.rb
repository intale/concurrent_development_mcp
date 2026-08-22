# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Renew do
  subject(:renew) { described_class.new }

  let(:renewed_at) { "2026-08-22T10:05:00.000000Z" }
  let(:current_expires_at) { "2026-08-22T10:10:00.000000Z" }
  let(:expires_at) { "2026-08-22T10:20:00.000000Z" }
  let(:lease_set_id) { "03919191-9191-7191-8191-919191919191" }
  let(:resources) do
    %w[app/a.rb app/b.rb].map.with_index do |path, index|
      resource = Coordinator::Write::FileResourceNormalizer.new.call(
        repository_id: "billing",
        kind: "file",
        path:,
        base_blob_oid: nil
      ).value!
      Coordinator::Write::LeaseReferenceV1.new(
        lease_id: format("%08d-9191-7191-8191-919191919191", index + 1),
        resource_key: resource.resource_key,
        resource_key_hash: resource.resource_key_hash,
        resource_kind: resource.kind,
        resource_path: resource.path,
        base_blob_oid: resource.base_blob_oid,
        fencing_token: index + 1
      )
    end.sort_by(&:resource_key_hash)
  end
  let(:attempt_state) do
    Coordinator::Write::Domain::Attempts::State.reduce(
      [
        Coordinator::Write::Events::AttemptAuthorizedV1.new(
          attempt_id: "A-LSE-A",
          change_set_id: "CS-LSE",
          work_item_id: "W-LSE-A",
          agent_id: "agent-a",
          base_snapshots: [
            Coordinator::Write::RepositorySnapshotV1.new(
              repository_id: "billing",
              object_format: "sha1",
              commit_oid: "a" * 40
            )
          ],
          authorized_at: "2026-08-22T10:00:00.000000Z"
        ),
        Coordinator::Write::Events::AttemptStartedV1.new(
          attempt_id: "A-LSE-A",
          change_set_id: "CS-LSE",
          work_item_id: "W-LSE-A",
          started_at: "2026-08-22T10:00:00.000000Z"
        ),
        Coordinator::Write::Events::WriteSetReservedV1.new(
          lease_set_id:,
          change_set_id: "CS-LSE",
          work_item_id: "W-LSE-A",
          attempt_id: "A-LSE-A",
          repository_id: "billing",
          policy_version: "coordinator-resource-key/v1",
          resources:,
          reserved_at: "2026-08-22T10:00:00.000000Z",
          expires_at: current_expires_at
        )
      ]
    )
  end
  let(:command) do
    Coordinator::Write::Commands::RenewLeaseSet.new(
      command_id: "cmd-renew-a",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id:,
      leases: resources.map do |reference|
        Coordinator::Write::LeaseRenewalReferenceV1.new(
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        )
      end,
      lease_duration_seconds: 900
    )
  end
  let(:observations) do
    resources.map do |reference|
      Coordinator::Write::CurrentLeaseObservationV1.new(
        reference:,
        state: lease_state(reference)
      )
    end
  end

  it "Given an exact current set, when renewing, then preserves every identity and extends one deadline" do
    result = renew.call(
      attempt_state:,
      current_observations: observations,
      command:,
      renewed_at:,
      expires_at:
    )

    expect(result).to be_success
    first, second, set = result.value!.events
    expect([ first, second ]).to all(be_a(Coordinator::Write::Events::ResourceLeaseRenewedV1))
    expect([ first, second ].map(&:lease_id)).to eq(resources.map(&:lease_id))
    expect([ first, second ].map(&:fencing_token)).to eq(resources.map(&:fencing_token))
    expect([ first, second ].map(&:expires_at).uniq).to eq([ expires_at ])
    expect(set).to be_a(Coordinator::Write::Events::WriteSetRenewedV1)
    expect(set.to_h).to include(
      lease_set_id:,
      resources: resources.map(&:to_h),
      resource_count: 2,
      renewed_at:,
      previous_expires_at: current_expires_at,
      expires_at:
    )
  end

  it "Given incomplete or stale submitted references, when renewing, then emits no facts" do
    incomplete = renew.call(
      attempt_state:,
      current_observations: observations,
      command: command.new(leases: command.leases.first(1)),
      renewed_at:,
      expires_at:
    )
    stale = renew.call(
      attempt_state:,
      current_observations: observations,
      command: command.new(
        leases: [ command.leases.first.new(fencing_token: 99), command.leases.last ]
      ),
      renewed_at:,
      expires_at:
    )

    expect(incomplete.failure.code).to eq(:lease_set_snapshot_mismatch)
    expect(stale.failure.code).to eq(:lease_reference_mismatch)
  end

  it "Given the current deadline has elapsed, when renewing, then rejects equality as expired" do
    result = renew.call(
      attempt_state: attempt_state.new(lease_expires_at: renewed_at),
      current_observations: observations.map { _1.new(state: _1.state.new(expires_at: renewed_at)) },
      command:,
      renewed_at:,
      expires_at:
    )

    expect(result.failure.code).to eq(:lease_set_expired)
  end

  it "Given a duration that does not move the deadline forward, when renewing, then emits no facts" do
    result = renew.call(
      attempt_state:,
      current_observations: observations,
      command:,
      renewed_at:,
      expires_at: current_expires_at
    )

    expect(result.failure.code).to eq(:lease_deadline_not_extended)
  end

  it "Given one member was superseded, when renewing, then rejects the complete set" do
    successor = observations.last.state.new(
      lease_id: "09919191-9191-7191-8191-919191919191",
      lease_set_id: "08919191-9191-7191-8191-919191919191",
      attempt_id: "A-LSE-B",
      agent_id: "agent-b",
      fencing_token: observations.last.state.fencing_token + 1
    )
    current = [ observations.first, observations.last.new(state: successor) ]

    result = renew.call(
      attempt_state:,
      current_observations: current,
      command:,
      renewed_at:,
      expires_at:
    )

    expect(result.failure.code).to eq(:lease_set_not_current)
    expect(result.failure.details).to include(current_attempt_id: "A-LSE-B")
  end

  private

  def lease_state(reference)
    Coordinator::Write::Domain::ResourceLeases::State.reduce(
      [
        Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
          lease_id: reference.lease_id,
          lease_set_id:,
          resource_key: reference.resource_key,
          resource_key_hash: reference.resource_key_hash,
          resource_kind: reference.resource_kind,
          resource_path: reference.resource_path,
          policy_version: "coordinator-resource-key/v1",
          mode: "exclusive",
          change_set_id: "CS-LSE",
          work_item_id: "W-LSE-A",
          attempt_id: "A-LSE-A",
          agent_id: "agent-a",
          repository_id: "billing",
          object_format: "sha1",
          base_commit_oid: "a" * 40,
          base_blob_oid: reference.base_blob_oid,
          fencing_token: reference.fencing_token,
          acquired_at: "2026-08-22T10:00:00.000000Z",
          expires_at: current_expires_at
        )
      ]
    )
  end
end
