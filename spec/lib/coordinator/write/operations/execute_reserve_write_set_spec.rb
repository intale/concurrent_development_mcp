# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteReserveWriteSet, :event_store do
  REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "denies an exhausted real marker boundary without recording a partial set" do
    start_attempts([
      [ "W-INT-A", "A-INT-A", "agent-a" ],
      [ "W-INT-B", "A-INT-B", "agent-b" ]
    ])
    resource_id = resolve("capacity/shared.rb")
    owner = operation.call(
      reserve_input(
        command_id: "cmd-capacity-owner", agent_id: "agent-a",
        work_item_id: "W-INT-A", attempt_id: "A-INT-A", resources: [ { resource_id: } ]
      )
    ).value!.data
    declaration = read_intention(owner.intentions.sole.intention_id).sole
    WorkIntentionHistoryFixture.exhaust_boundary(event_store:, declaration:)

    result = operation.call(
      reserve_input(
        command_id: "cmd-capacity-requester", agent_id: "agent-b",
        work_item_id: "W-INT-B", attempt_id: "A-INT-B", resources: [ { resource_id: } ]
      )
    )

    expect(result.failure).to have_attributes(code: :resource_boundary_maintenance_required)
    expect(result.failure.details).to include(
      maximum_delta_event_count: Coordinator::Write::EventQueries::WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT
    )
    expect(Coordinator::Write::WorkIntentionSetLoader.new(event_store:).find_by_attempt("A-INT-B")).to be_nil
    mapped = Coordinator::Write::Tasks::ToolResultMapper.new.call(
      result, command_id: "cmd-capacity-requester", tool_name: "work_intention_set_declare"
    )
    expect(mapped).to have_attributes(is_error: true)
    expect(mapped.structured_content.status).to eq("limit_reached")
  end

  it "records one cohesive intention plus one set-membership fact per resource" do
    start_attempts([ [ "W-INT-A", "A-INT-A", "agent-a" ] ])
    resources = [ resolve("app/services/capture.rb"), resolve("db/schema.rb") ]

    result = operation.call(
      reserve_input(
        command_id: "cmd-declare-intentions",
        agent_id: "agent-a",
        work_item_id: "W-INT-A",
        attempt_id: "A-INT-A",
        resources: resources.map { { resource_id: _1, purpose: "Implement the scoped change" } }
      )
    )

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to have_attributes(
      policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION,
      repository_id: REPOSITORY_ID
    )
    expect(receipt.intentions.map(&:resource_id)).to contain_exactly(*resources)

    set_events = read_set(receipt.intention_set_id)
    expect(set_events.map(&:type)).to eq(
      [ "WorkIntentionSetCreated", "WorkIntentionAddedToSet", "WorkIntentionAddedToSet" ]
    )
    expect(set_events.first.data.keys).to contain_exactly(
      "set_id", "attempt_id", "work_item_id", "change_set_id", "repository_id"
    )

    receipt.intentions.each do |reference|
      event = read_intention(reference.intention_id).sole
      expect(event).to have_attributes(type: "ResourceWorkIntentionDeclared", stream_revision: 0)
      expect(event.stream.stream_id).to eq(reference.intention_id)
      expect(event.data.keys).to contain_exactly(
        "intention_id", "set_id", "resource_id", "repository_id", "change_set_id",
        "work_item_id", "attempt_id", "agent_id", "mode", "purpose", "context",
        "object_format", "base_commit_oid", "base_blob_oid", "fencing_token", "expires_at"
      )
      expect(event.data).to include(
        "resource_id" => reference.resource_id,
        "mode" => "shared",
        "purpose" => "Implement the scoped change"
      )
      expect(event.markers).to include(
        "work-intention:#{reference.intention_id}",
        "work-intention-set:#{receipt.intention_set_id}",
        "resource:#{reference.resource_id}"
      )
      expect(event.markers).to include(a_string_matching(/role=\d+:resource-exact(?:\||$)/))
      expect(event.markers).to include(a_string_matching(/role=\d+:resource-within(?:\||$)/))
    end
  end

  it "allows two agents to declare shared intentions for the same resource" do
    start_attempts(
      [
        [ "W-INT-A", "A-INT-A", "agent-a" ],
        [ "W-INT-B", "A-INT-B", "agent-b" ]
      ]
    )
    resource_id = resolve("config/routes.rb")
    inputs = [
      reserve_input(
        command_id: "cmd-shared-a",
        agent_id: "agent-a",
        work_item_id: "W-INT-A",
        attempt_id: "A-INT-A",
        resources: [ { resource_id:, purpose: "Add routes for feature A" } ]
      ),
      reserve_input(
        command_id: "cmd-shared-b",
        agent_id: "agent-b",
        work_item_id: "W-INT-B",
        attempt_id: "A-INT-B",
        resources: [ { resource_id:, purpose: "Add routes for feature B" } ]
      )
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results).to all(be_success)
    fences = results.map { _1.value!.data.intentions.sole.fencing_token }
    expect(fences).to contain_exactly(1, 2)
  end

  it "rejects shared or exclusive work when an overlapping exclusive intention is active" do
    start_attempts(
      [
        [ "W-INT-A", "A-INT-A", "agent-a" ],
        [ "W-INT-B", "A-INT-B", "agent-b" ]
      ]
    )
    directory = resolve("curriculum/chapter-2", kind: "directory")
    child = resolve("curriculum/chapter-2/paragraph.md")
    owner = operation.call(
      reserve_input(
        command_id: "cmd-exclusive-owner",
        agent_id: "agent-a",
        work_item_id: "W-INT-A",
        attempt_id: "A-INT-A",
        resources: [
          {
            resource_id: directory,
            mode: "exclusive",
            purpose: "Rewrite the chapter translation",
            context: "Paragraph edits would be invalidated by the rewrite"
          }
        ]
      )
    )
    expect(owner).to be_success

    blocked = operation.call(
      reserve_input(
        command_id: "cmd-shared-child",
        agent_id: "agent-b",
        work_item_id: "W-INT-B",
        attempt_id: "A-INT-B",
        resources: [ { resource_id: child, purpose: "Correct one paragraph" } ]
      )
    )

    expect(blocked.failure).to have_attributes(code: :work_intention_conflict)
    blocker = blocked.failure.details.fetch(:blockers).sole
    expect(blocker).to include(
      resource_id: directory,
      resource_kind: "directory",
      resource_path: "curriculum/chapter-2",
      mode: "exclusive",
      owner_agent_id: "agent-a",
      owner_attempt_id: "A-INT-A",
      purpose: "Rewrite the chapter translation",
      context: "Paragraph edits would be invalidated by the rewrite"
    )
    expect(blocker.fetch(:scope)).to include(
      repository_id: REPOSITORY_ID,
      change_set_id: "CS-LSE",
      work_item_id: "W-INT-A"
    )
  end

  it "does not treat a file path prefix as an ancestor overlap" do
    start_attempts([ [ "W-INT-A", "A-INT-A", "agent-a" ] ])
    prefix = resolve("app/services")
    child = resolve("app/services/capture.rb")

    result = operation.call(
      reserve_input(
        command_id: "cmd-file-prefixes",
        agent_id: "agent-a",
        work_item_id: "W-INT-A",
        attempt_id: "A-INT-A",
        resources: [
          { resource_id: prefix, mode: "exclusive", purpose: "Edit the prefix-named file" },
          { resource_id: child, mode: "exclusive", purpose: "Edit the nested file" }
        ]
      )
    )

    expect(result).to be_success
    expect(result.value!.data.intentions.length).to eq(2)
  end

  it "rejects duplicate declaration and invalid resource identities without partial facts" do
    start_attempts([ [ "W-INT-A", "A-INT-A", "agent-a" ] ])
    resource_id = resolve("app/replay.rb")
    input = reserve_input(
      command_id: "cmd-declare-once",
      agent_id: "agent-a",
      work_item_id: "W-INT-A",
      attempt_id: "A-INT-A",
      resources: [ { resource_id: } ]
    )

    original = operation.call(input)
    duplicate = operation.call(input)
    missing_id = SecureRandom.uuid_v7
    missing = operation.call(
      reserve_input(
        command_id: "cmd-missing-resource",
        agent_id: "agent-a",
        work_item_id: "W-INT-A",
        attempt_id: "A-INT-A",
        resources: [ { resource_id: missing_id } ]
      )
    )

    expect(original).to be_success
    expect(duplicate.failure).to have_attributes(code: :work_intention_set_already_declared)
    expect(missing.failure).to have_attributes(code: :resource_not_found, details: { resource_id: missing_id })
    expect(read_intention(original.value!.data.intentions.sole.intention_id).length).to eq(1)
  end

  def start_attempts(attempts)
    ResourceLeaseOperationScenario.start_attempts(event_store:, attempts:)
  end

  def resolve(path, kind: "file")
    ResourceScenario.resolve(event_store:, repository_id: REPOSITORY_ID, kind:, path:)
  end

  def reserve_input(command_id:, agent_id:, work_item_id:, attempt_id:, resources:)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      repository_id: REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources:,
      ttl_seconds: 900
    }
  end

  def read_set(set_id)
    event_store.read(
      streams.work_intention_set(set_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE
    )
  end

  def read_intention(intention_id)
    event_store.read_grouped(
      streams.resource_work_intention(intention_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_STATE
    ).reverse
  end
end
