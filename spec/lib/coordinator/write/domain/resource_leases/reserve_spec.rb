# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Reserve do
  subject(:reserve) { described_class.new }

  let(:preparer) { Coordinator::Write::Operations::PrepareReserveWriteSet.new }
  let(:command) do
    preparer.call(
      command_id: "cmd-lse-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      repository_id:,
      base_commit_oid: "a" * 40,
      resources: [
        { kind: "file", path: "app/models/user.rb" },
        { kind: "file", path: "db/schema.rb", base_blob_oid: "b" * 40 }
      ],
      lease_duration_seconds: 900
    ).value!
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
              repository_id:,
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
        )
      ]
    )
  end
  let(:lease_states) do
    command.resources.map { Coordinator::Write::Domain::ResourceLeases::State.initial }
  end
  let(:lease_ids) do
    [
      "01919191-9191-7191-8191-919191919191",
      "02919191-9191-7191-8191-919191919191"
    ]
  end

  it "Given an active matching Attempt and free resources, when reserving, then returns every lease and reservation fact" do
    result = reserve.call(
      attempt_state:,
      lease_states:,
      command:,
      lease_set_id: "03919191-9191-7191-8191-919191919191",
      lease_ids:,
      acquired_at: "2026-08-22T10:00:00.000000Z",
      expires_at: "2026-08-22T10:15:00.000000Z"
    )

    expect(result).to be_success
    events = result.value!.events
    expect(events.map(&:class)).to eq(
      [
        Coordinator::Write::Events::ResourceLeaseAcquiredV1,
        Coordinator::Write::Events::ResourceLeaseAcquiredV1,
        Coordinator::Write::Events::WriteSetReservedV1
      ]
    )
    expect(events.first(2).map(&:fencing_token)).to eq([ 1, 1 ])
    expect(events.last.resources.map(&:lease_id)).to eq(lease_ids)
  end

  it "returns zero-event scope, owner, base, and already-reserved denials" do
    cases = {
      attempt_not_found: Coordinator::Write::Domain::Attempts::State.initial,
      attempt_scope_mismatch: attempt_state.new(work_item_id: "W-OTHER"),
      attempt_owner_mismatch: attempt_state.new(agent_id: "agent-b"),
      repository_base_mismatch: attempt_state.new(
        base_snapshots: [
          Coordinator::Write::RepositorySnapshotV1.new(
            repository_id:,
            object_format: "sha1",
            commit_oid: "c" * 40
          )
        ]
      ),
      write_set_already_reserved: attempt_state.new(
        lease_set_id: "04919191-9191-7191-8191-919191919191"
      )
    }

    cases.each do |code, state|
      result = reserve.call(
        attempt_state: state,
        lease_states:,
        command:,
        lease_set_id: "03919191-9191-7191-8191-919191919191",
        lease_ids:,
        acquired_at: "2026-08-22T10:00:00.000000Z",
        expires_at: "2026-08-22T10:15:00.000000Z"
      )
      expect(result.failure.code).to eq(code)
    end
  end

  it "returns one precise busy denial and no plan when any resource is active" do
    occupied = reserve.call(
      attempt_state:,
      lease_states:,
      command:,
      lease_set_id: "03919191-9191-7191-8191-919191919191",
      lease_ids:,
      acquired_at: "2026-08-22T10:00:00.000000Z",
      expires_at: "2026-08-22T10:15:00.000000Z"
    ).value!.events.first
    states = [ Coordinator::Write::Domain::ResourceLeases::State.reduce([ occupied ]), lease_states.last ]

    result = reserve.call(
      attempt_state:,
      lease_states: states,
      command:,
      lease_set_id: "05919191-9191-7191-8191-919191919191",
      lease_ids: lease_ids.reverse,
      acquired_at: "2026-08-22T10:01:00.000000Z",
      expires_at: "2026-08-22T10:16:00.000000Z"
    )

    expect(result.failure.to_h).to include(code: :lease_busy)
    expect(result.failure.details).to include(
      resource_key_hash: command.resources.first.resource_key_hash,
      owner_attempt_id: "A-LSE-A",
      fencing_token: 1
    )
  end

  it "treats an active parent directory as a structural conflict for a requested child file" do
    child = command.resources.first.new(
      path: "app/models/user.rb",
      resource_key: "repo:#{repository_id}:file:app/models/user.rb",
      resource_key_hash: "sha256:#{'a' * 64}"
    )
    directory = command.resources.first.new(
      kind: "directory",
      path: "app/models",
      resource_key: "repo:#{repository_id}:directory:app/models",
      resource_key_hash: "sha256:#{'b' * 64}"
    )
    blocking = Coordinator::Write::Domain::ResourceLeases::State.reduce(
      [
        Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
          lease_id: "06919191-9191-7191-8191-919191919191",
          lease_set_id: "07919191-9191-7191-8191-919191919191",
          resource_key: directory.resource_key,
          resource_key_hash: directory.resource_key_hash,
          resource_kind: directory.kind,
          resource_path: directory.path,
          policy_version: directory.policy_version,
          mode: "exclusive",
          change_set_id: "CS-OTHER",
          work_item_id: "W-OTHER",
          attempt_id: "A-OTHER",
          agent_id: "agent-b",
          repository_id:,
          object_format: "sha1",
          base_commit_oid: "a" * 40,
          base_blob_oid: nil,
          fencing_token: 1,
          acquired_at: "2026-08-22T10:00:00.000000Z",
          expires_at: "2026-08-22T10:15:00.000000Z"
        )
      ]
    )

    result = reserve.call(
      attempt_state:,
      lease_states: [ Coordinator::Write::Domain::ResourceLeases::State.initial, blocking ],
      command: command.new(resources: [ child ]),
      lease_set_id: "03919191-9191-7191-8191-919191919191",
      lease_ids: [ lease_ids.first ],
      acquired_at: "2026-08-22T10:01:00.000000Z",
      expires_at: "2026-08-22T10:16:00.000000Z"
    )

    expect(result.failure).to have_attributes(code: :lease_busy)
    expect(result.failure.details).to include(resource_key_hash: child.resource_key_hash, owner_attempt_id: "A-OTHER")
  end

  def repository_id
    RepositoryScenario::DEFAULT_REPOSITORY_ID
  end
end
