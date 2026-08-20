# frozen_string_literal: true

RSpec.describe Coordinator::Queries::OperationGet, :event_store, :read_model do
  let(:event_store) { Coordinator::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::StreamFactory.new }
  let(:projector) { Coordinator::Projectors::CoordContextV1.new }
  subject(:query) do
    described_class.new(
      completion_lookup: Coordinator::CommandCompletionLookup.new(event_store:),
      progress: Coordinator::CoordContextProgress.new
    )
  end

  it "falls back to the authoritative Command stream and names each missing exact barrier" do
    completion = create_change_set

    pending = query.call(command_id: "cmd-100").value!
    expect(pending.status).to eq("pending_projection")
    expect(pending.data.result).to eq(completion.data)
    expect(pending.data.projection_progress.sole.missing_barriers).to eq(
      completion.projection_barriers.coord_context_v1
    )

    change_set_events.each { projector.call(_1) }
    current = query.call(command_id: "cmd-100").value!
    expect(current.status).to eq("ok")
    expect(current.projection_status).to eq("current_for_requested_command")
  end

  it "does not treat one processed sibling as completion" do
    create_change_set
    completion = create_work_item
    change_set_events.first(2).each { projector.call(_1) }
    projector.call(work_item_events.sole)

    pending = query.call(command_id: "cmd-200").value!
    expect(pending.status).to eq("pending_projection")
    expect(pending.data.projection_progress.sole.missing_barriers).to eq(
      [ completion.projection_barriers.coord_context_v1.find { _1.stream_name == "ChangeSet" } ]
    )

    membership = change_set_events.find { _1.type == "WorkItemAddedToChangeSet" }
    projector.call(membership)
    expect(query.call(command_id: "cmd-200").value!.status).to eq("ok")
  end

  it "returns not_found and typed invalid input without reading an unbounded stream" do
    expect(query.call(command_id: "cmd-404").value!.status).to eq("not_found")
    expect(query.call(command_id: "bad id").value!.status).to eq("invalid")
  end

  def create_change_set
    Coordinator::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "cmd-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      goal: "Coordinate repositories",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
  end

  def create_work_item
    Coordinator::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "cmd-200",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      repository_id: "billing",
      goal: "Implement billing",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
  end

  def change_set_events
    event_store.read(
      streams.change_set("CS-100"),
      Coordinator::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events
    event_store.read(
      streams.work_item("W-100"),
      Coordinator::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
  end
end
