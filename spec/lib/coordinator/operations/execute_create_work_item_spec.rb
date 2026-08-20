# frozen_string_literal: true

RSpec.describe Coordinator::Operations::ExecuteCreateWorkItem, :event_store do
  let(:event_store) { Coordinator::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  let(:input) do
    {
      command_id: "cmd-200",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    }
  end

  before do
    create_change_set("CS-100")
  end

  it "persists both cross-stream facts and the durable completion through the real store" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to eq(
      Coordinator::CommandReceiptData::WorkItem.new(
        change_set_id: "CS-100",
        work_item_id: "W-200"
      )
    )
    expect(work_item_events("W-200").map(&:type)).to eq([ "WorkItemCreated" ])
    expect(change_set_events("CS-100").map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined", "WorkItemAddedToChangeSet" ]
    )
    expect(command_events("cmd-200").map(&:type)).to eq([ "CommandCompleted" ])
    expect(completion.projection_barriers.coord_context_v1.map(&:to_h)).to contain_exactly(
      hash_including(stream_name: "WorkItem", stream_revision: 0),
      hash_including(stream_name: "ChangeSet", stream_revision: 2)
    )
  end

  it "writes the routing markers on real persisted events" do
    operation.call(input)

    created = work_item_events("W-200").sole
    membership = change_set_events("CS-100").last
    expect(created.markers).to eq(
      [ "change-set:CS-100", "command:cmd-200", "repository:billing", "work-item:W-200" ]
    )
    expect(membership.markers).to eq(
      [ "change-set:CS-100", "command:cmd-200", "work-item:W-200" ]
    )
  end

  it "replays the exact persisted result without another real append" do
    original = operation.call(input)
    original_ids = persisted_ids

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(persisted_ids).to eq(original_ids)
  end

  it "rejects reuse of the command ID with changed accepted input" do
    operation.call(input)

    result = operation.call(input.merge(goal: "A different goal"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(work_item_events("W-200").length).to eq(1)
    expect(command_events("cmd-200").length).to eq(1)
  end

  it "returns a zero-event duplicate denial without completing the losing command" do
    operation.call(input)

    result = operation.call(input.merge(command_id: "cmd-201"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:work_item_already_exists)
    expect(command_events("cmd-201")).to be_empty
  end

  it "returns a zero-event denial when the ChangeSet is absent" do
    missing_input = input.merge(
      command_id: "cmd-missing",
      change_set_id: "CS-missing",
      work_item_id: "W-missing"
    )

    result = operation.call(missing_input)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_not_found)
    expect(work_item_events("W-missing")).to be_empty
    expect(command_events("cmd-missing")).to be_empty
  end

  it "serializes concurrent real commands so exactly one creates the WorkItem" do
    competing_inputs = [
      input.merge(command_id: "cmd-concurrent-1"),
      input.merge(command_id: "cmd-concurrent-2")
    ]

    results = competing_inputs.map do |competing_input|
      Thread.new { described_class.new(event_store:).call(competing_input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:work_item_already_exists)
    expect(work_item_events("W-200").length).to eq(1)
    expect(change_set_events("CS-100").count { _1.type == "WorkItemAddedToChangeSet" }).to eq(1)
    expect(competing_inputs.count { command_events(_1.fetch(:command_id)).one? }).to eq(1)
  end

  def create_change_set(change_set_id)
    Coordinator::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate billing changes",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::EventReadCriteria.new(
        event_types: [ "WorkItemCreated" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::EventQueries::COMMAND_COMPLETION)
  end

  def persisted_ids
    work_item_events("W-200").map(&:id) +
      change_set_events("CS-100").select { _1.type == "WorkItemAddedToChangeSet" }.map(&:id) +
      command_events("cmd-200").map(&:id)
  end
end
