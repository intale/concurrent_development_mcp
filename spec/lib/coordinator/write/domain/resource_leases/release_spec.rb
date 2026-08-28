# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Release do
  subject(:release) { described_class.new }

  let(:released_at) { "2026-08-22T10:20:00.000000Z" }
  let(:current_expires_at) { "2026-08-22T10:10:00.000000Z" }
  let(:lease_set_id) { "03919191-9191-7191-8191-919191919191" }
  let(:resources) do
    %w[app/a.rb app/b.rb].map.with_index do |path, index|
      resource = Coordinator::Write::FileResourceNormalizer.new.call(
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
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
              repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
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
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
          policy_version: "coordinator-resource-key/v1",
          resources:,
          reserved_at: "2026-08-22T10:00:00.000000Z",
          expires_at: current_expires_at
        )
      ]
    )
  end
  let(:command) do
    Coordinator::Write::Commands::ReleaseLeaseSet.new(
      command_id: "cmd-release-a",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id:,
      leases: resources.map do |reference|
        Coordinator::Write::LeaseReleaseReferenceV1.new(
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        )
      end
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

  it "Given an exact current set, when releasing, then closes every member without changing identity" do
    result = release.call(
      attempt_state:,
      current_observations: observations,
      command:,
      released_at:
    )

    expect(result).to be_success
    decision = result.value!
    expect(decision).to be_release
    first, second, set = decision.plan.events
    expect([ first, second ]).to all(be_a(Coordinator::Write::Events::ResourceLeaseReleasedV1))
    expect([ first, second ].map(&:lease_id)).to eq(resources.map(&:lease_id))
    expect([ first, second ].map(&:fencing_token)).to eq(resources.map(&:fencing_token))
    expect([ first, second ].map(&:released_at).uniq).to eq([ released_at ])
    expect(set).to be_a(Coordinator::Write::Events::WriteSetReleasedV1)
    expect(set.to_h).to include(
      lease_set_id:,
      resources: resources.map(&:to_h),
      resource_count: 2,
      previous_expires_at: current_expires_at,
      released_at:
    )
  end

  it "Given the deadline elapsed but identities remain current, when releasing, then cleanup still succeeds" do
    result = release.call(
      attempt_state:,
      current_observations: observations,
      command:,
      released_at:
    )

    expect(released_at).to be > current_expires_at
    expect(result).to be_success
    expect(result.value!).to be_release
  end

  it "Given incomplete or stale submitted references, when releasing, then emits no facts" do
    incomplete = release.call(
      attempt_state:,
      current_observations: observations,
      command: command.new(leases: command.leases.first(1)),
      released_at:
    )
    stale = release.call(
      attempt_state:,
      current_observations: observations,
      command: command.new(
        leases: [ command.leases.first.new(fencing_token: 99), command.leases.last ]
      ),
      released_at:
    )

    expect(incomplete.failure.code).to eq(:lease_set_snapshot_mismatch)
    expect(stale.failure.code).to eq(:lease_reference_mismatch)
  end

  it "Given one member was acquired by a successor, when releasing, then rejects the complete old set" do
    successor = observations.last.state.new(
      lease_id: "09919191-9191-7191-8191-919191919191",
      lease_set_id: "08919191-9191-7191-8191-919191919191",
      attempt_id: "A-LSE-B",
      agent_id: "agent-b",
      fencing_token: observations.last.state.fencing_token + 1
    )
    current = [ observations.first, observations.last.new(state: successor) ]

    result = release.call(
      attempt_state:,
      current_observations: current,
      command:,
      released_at:
    )

    expect(result.failure.code).to eq(:lease_set_not_current)
    expect(result.failure.details).to include(current_attempt_id: "A-LSE-B")
  end

  it "Given the exact set was already released, when releasing, then selects durable-result replay" do
    write_set_release = Coordinator::Write::Events::WriteSetReleasedV1.new(
      lease_set_id:,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      policy_version: "coordinator-resource-key/v1",
      resources:,
      resource_count: 2,
      previous_expires_at: current_expires_at,
      released_at: "2026-08-22T10:15:00.000000Z"
    )

    result = release.call(
      attempt_state: attempt_state.apply(write_set_release),
      current_observations: observations,
      command:,
      released_at:
    )

    expect(result).to be_success
    expect(result.value!).not_to be_release
    expect(result.value!.kind).to eq("already_released")
    expect(result.value!.plan).to be_nil
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
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
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
