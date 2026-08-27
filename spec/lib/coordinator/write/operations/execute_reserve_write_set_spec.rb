# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteReserveWriteSet, :event_store do
  RESERVE_REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  subject(:operation) { described_class.new(event_store:) }

  let(:input) do
    reserve_input(
      command_id: "cmd-lse-100",
      agent_id: "agent-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      paths: [ "app/services/capture.rb", "db/schema.rb" ]
    )
  end

  it "atomically persists every resource acquisition, Attempt reservation, and exact completion" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])

    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to be_a(Coordinator::Write::CommandReceiptData::LeaseSet)
    expect(completion.data.to_h).to include(
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      repository_id: RESERVE_REPOSITORY_ID,
      policy_version: "coordinator-resource-key/v3"
    )
    expect(completion.data.resources.map(&:fencing_token)).to eq([ 1, 1 ])
    expect(completion.emitted_events.map(&:stream_name)).to eq(
      [ "ResourceLease", "ResourceLease", "Attempt" ]
    )
    expect(attempt_events("A-LSE-A").map(&:type)).to eq(
      [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved" ]
    )
    expect(command_events("cmd-lse-100").map(&:type)).to eq([ "CommandCompleted" ])

    input.fetch(:resources).each do |resource|
      acquisition = lease_events(resource.fetch(:path)).sole
      expect(acquisition.data).to include(
        "mode" => "exclusive",
        "attempt_id" => "A-LSE-A",
        "agent_id" => "agent-a",
        "fencing_token" => 1
      )
      expect(acquisition.metadata).to include(
        "policy_version" => "coordinator-resource-key/v3"
      )
      expect(acquisition.metadata).not_to have_key("correlation_id")
      expect(acquisition.markers).to include(
        "scope:#{RepositoryScenario::DEFAULT_SCOPE}",
        "repository:#{RESERVE_REPOSITORY_ID}",
        "resource-kind:file",
        "resource-key-hash:#{acquisition.data.fetch('resource_key_hash')}"
      )
      expect(acquisition.markers.grep(/\Acompound:resource-identity:v1:sha256:/).length).to eq(1)
      expect(acquisition.markers.grep(/\Aresource-path:v1:/).length).to eq(1)
    end
  end

  it "replays the exact byte-preserving completion and rejects changed command reuse" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    original = operation.call(input)
    original_ids = reservation_event_ids(input)

    exact_replay = operation.call(input)
    changed = operation.call(input.merge(lease_duration_seconds: 901))

    expect(exact_replay).to be_success
    expect(exact_replay.value!).to eq(original.value!)
    expect(changed.failure.code).to eq(:command_id_reused)
    expect(reservation_event_ids(input)).to eq(original_ids)
  end

  it "returns precise zero-fact Attempt, owner, base, and existing-reservation denials" do
    RepositoryScenario.register(event_store:)
    missing = operation.call(input.merge(command_id: "cmd-missing", attempt_id: "A-MISSING"))
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    wrong_owner = operation.call(input.merge(command_id: "cmd-owner", actor: { kind: "agent", id: "agent-b" }))
    wrong_base = operation.call(input.merge(command_id: "cmd-base", base_commit_oid: "b" * 40))
    operation.call(input.merge(command_id: "cmd-first"))
    already_reserved = operation.call(input.merge(command_id: "cmd-second"))

    expect(missing.failure.code).to eq(:attempt_not_found)
    expect(wrong_owner.failure.code).to eq(:attempt_owner_mismatch)
    expect(wrong_base.failure.code).to eq(:repository_base_mismatch)
    expect(already_reserved.failure.code).to eq(:write_set_already_reserved)
    expect([ "cmd-missing", "cmd-owner", "cmd-base", "cmd-second" ].flat_map { command_events(_1) }).to be_empty
  end

  it "rejects an unregistered repository from authoritative event facts" do
    unregistered_id = "01a03deb-6f55-74ba-bcc0-afd02e7b14dd"
    result = operation.call(input.merge(command_id: "cmd-unregistered", repository_id: unregistered_id))

    expect(result.failure).to have_attributes(
      code: :repository_not_registered,
      details: { repository_id: unregistered_id }
    )
    expect(command_events("cmd-unregistered")).to be_empty
  end

  it "acquires all requested resources or none when one resource is busy" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    operation.call(
      reserve_input(
        command_id: "cmd-owner",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        paths: [ "shared.rb" ]
      )
    ).value!

    result = operation.call(
      reserve_input(
        command_id: "cmd-contender",
        agent_id: "agent-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        paths: [ "free.rb", "shared.rb" ]
      )
    )

    expect(result.failure.code).to eq(:lease_busy)
    expect(lease_events("free.rb")).to be_empty
    expect(attempt_events("A-LSE-B").none? { _1.type == "WriteSetReserved" }).to be(true)
    expect(command_events("cmd-contender")).to be_empty
  end

  it "serializes overlapping dynamic resource sets so exactly one complete set wins" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    inputs = [
      reserve_input(
        command_id: "cmd-race-a",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        paths: [ "a.rb", "shared.rb" ]
      ),
      reserve_input(
        command_id: "cmd-race-b",
        agent_id: "agent-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        paths: [ "shared.rb", "b.rb" ]
      )
    ]

    results = inputs.map do |candidate|
      Thread.new { described_class.new(event_store:).call(candidate) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:lease_busy)
    expect(lease_events("shared.rb").length).to eq(1)
    expect(%w[a.rb b.rb].sum { lease_events(_1).length }).to eq(1)
    expect(inputs.sum { command_events(_1.fetch(:command_id)).length }).to eq(1)
  end

  it "re-evaluates a concurrent directory/child-file DCB so exactly one Task decision wins" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    inputs = [
      reserve_input(
        command_id: "cmd-directory-race",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        resources: [ { kind: "directory", path: "app/models" } ]
      ),
      reserve_input(
        command_id: "cmd-child-race",
        agent_id: "agent-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        resources: [ { kind: "file", path: "app/models/user.rb" } ]
      )
    ]

    results = inputs.map do |candidate|
      Thread.new { described_class.new(event_store:).call(candidate) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure).to have_attributes(code: :lease_busy)
    expect(
      lease_events("app/models", kind: "directory").length + lease_events("app/models/user.rb").length
    ).to eq(1)
    expect(inputs.sum { command_events(_1.fetch(:command_id)).length }).to eq(1)
  end

  it "allows a file path and a child file path because neither lease covers descendants" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    inputs = [
      reserve_input(
        command_id: "cmd-file-parent",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        resources: [ { kind: "file", path: "app/models" } ]
      ),
      reserve_input(
        command_id: "cmd-file-child",
        agent_id: "agent-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        resources: [ { kind: "file", path: "app/models/user.rb" } ]
      )
    ]

    results = inputs.map do |candidate|
      Thread.new { described_class.new(event_store:).call(candidate) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(lease_events("app/models").length).to eq(1)
    expect(lease_events("app/models/user.rb").length).to eq(1)
  end

  it "returns a typed zero-fact denial when the selected DCB history exceeds its explicit bound" do
    seed_active_attempts([ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    marker = Coordinator::Write::RepositoryMarkerBuilder.new.resource_boundary_markers(
      repository_id: RESERVE_REPOSITORY_ID,
      resource_kind: "file",
      resource_path: "bounded.rb"
    ).sole
    events = 257.times.map do
      PgEventstore::Event.new(
        id: Coordinator::Shared::IdGenerator.new.uuid_v7,
        type: "ResourceLeaseAcquired",
        data: {},
        metadata: { "schema_version" => 1 },
        markers: [ marker ]
      )
    end
    event_store.append(streams.resource_lease("sha256:#{'f' * 64}"), events)

    result = operation.call(
      reserve_input(
        command_id: "cmd-boundary-overflow",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        paths: [ "bounded.rb" ]
      )
    )

    expect(result.failure).to have_attributes(code: :resource_boundary_history_limit_exceeded)
    expect(command_events("cmd-boundary-overflow")).to be_empty
    expect(attempt_events("A-LSE-A").none? { _1.type == "WriteSetReserved" }).to be(true)
  end

  it "allows disjoint dynamic resource sets to complete independently" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    inputs = [
      reserve_input(
        command_id: "cmd-disjoint-a",
        agent_id: "agent-a",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        paths: [ "a.rb" ]
      ),
      reserve_input(
        command_id: "cmd-disjoint-b",
        agent_id: "agent-b",
        work_item_id: "W-LSE-B",
        attempt_id: "A-LSE-B",
        paths: [ "b.rb" ]
      )
    ]

    results = inputs.map do |candidate|
      Thread.new { described_class.new(event_store:).call(candidate) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(lease_events("a.rb").length).to eq(1)
    expect(lease_events("b.rb").length).to eq(1)
  end

  it "reacquires exactly at expiry with a monotonically greater fencing token" do
    seed_active_attempts(
      [
        [ "W-LSE-A", "A-LSE-A", "agent-a" ],
        [ "W-LSE-B", "A-LSE-B", "agent-b" ]
      ]
    )
    first = reserve_input(
      command_id: "cmd-expiry-a",
      agent_id: "agent-a",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      paths: [ "expiring.rb" ],
      lease_duration_seconds: 30
    )
    second = reserve_input(
      command_id: "cmd-expiry-b",
      agent_id: "agent-b",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B",
      paths: [ "expiring.rb" ],
      lease_duration_seconds: 30
    )

    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) { operation.call(first).value! }
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) { operation.call(second).value! }

    expect(lease_events("expiring.rb").map { _1.data.fetch("fencing_token") }).to eq([ 1, 2 ])
  end

  it "rejects resource bounds before opening the target transaction" do
    result = operation.call(
      input.merge(resources: 33.times.map { { kind: "file", path: "file-#{_1}.rb" } })
    )

    expect(result.failure.code).to eq(:invalid_input)
    expect(command_events("cmd-lse-100")).to be_empty
    expect(attempt_events("A-LSE-A")).to be_empty
  end

  def reserve_input(
    command_id:,
    agent_id:,
    work_item_id:,
    attempt_id:,
    paths: nil,
    resources: nil,
    lease_duration_seconds: 900
  )
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      repository_id: RESERVE_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: resources || paths.map { { kind: "file", path: _1 } },
      lease_duration_seconds:
    }
  end

  def seed_active_attempts(attempts)
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE",
      goal: "Coordinate resource leases",
      acceptance_criteria: [ "Overlapping agents cannot both write" ]
    ).value!

    attempts.each do |work_item_id, _attempt_id, _agent_id|
      Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
        command_id: "seed-create-#{work_item_id}",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-LSE",
        work_item_id:,
        repository_id: RESERVE_REPOSITORY_ID,
        goal: "Implement #{work_item_id}",
        acceptance_criteria: [ "The work is verifiable" ]
      ).value!
    end

    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE"
    ).value!
    activation = event_store.read(
      streams.change_set("CS-LSE"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)

    attempts.each do |work_item_id, attempt_id, agent_id|
      Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
        command_id: "seed-acquire-#{attempt_id}",
        actor: { kind: "agent", id: agent_id },
        change_set_id: "CS-LSE",
        work_item_id:,
        attempt_id:,
        base_snapshots: [ { repository_id: RESERVE_REPOSITORY_ID, commit_oid: "a" * 40 } ]
      ).value!
    end
  end

  def lease_events(path, kind: "file")
    resource = normalizer.call(
      repository_id: RESERVE_REPOSITORY_ID,
      scope: RepositoryScenario::DEFAULT_SCOPE,
      kind:,
      path:,
      base_blob_oid: nil
    ).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceLeaseAcquired" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def attempt_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_WRITE_SET_RESERVATION
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def reservation_event_ids(arguments)
    arguments.fetch(:resources).flat_map do |resource|
      lease_events(resource.fetch(:path), kind: resource.fetch(:kind)).map(&:id)
    end +
      attempt_events(arguments.fetch(:attempt_id)).select { _1.type == "WriteSetReserved" }.map(&:id) +
      command_events(arguments.fetch(:command_id)).map(&:id)
  end
end
