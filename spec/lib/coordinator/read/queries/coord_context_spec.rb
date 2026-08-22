# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CoordContext, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:projector) { Coordinator::Read::Projectors::CoordContextV1.new }

  subject(:query) { described_class.new }

  it "serves an existing stale context immediately and supports observed-view cache tokens" do
    create_change_set
    create_work_item
    change_set_events.first(2).each { projector.call(_1) }

    expect(query.call(work_item_id: "W-100").value!.status).to eq("not_found")

    projector.call(work_item_events.sole)
    stale = query.call(work_item_id: "W-100").value!
    expect(stale.status).to eq("ok")
    expect(stale.data.context.work_items.sole.work_item_id).to eq("W-100")
    expect(stale.to_h).not_to include(:projection_status)

    projector.call(change_set_events.find { _1.type == "WorkItemAddedToChangeSet" })
    current = query.call(work_item_id: "W-100").value!
    expect(current.status).to eq("ok")

    unchanged = query.call(work_item_id: "W-100", context_token: current.context_token).value!
    expect(unchanged.status).to eq("not_modified")
    expect(unchanged.context_token).to eq(current.context_token)
  end

  it "rejects ambiguous roots and the removed causal-freshness parameter" do
    create_change_set
    change_set_events.each { projector.call(_1) }

    expect(query.call(change_set_id: "CS-100", work_item_id: "W-100").value!.status).to eq("invalid")
    expect(query.call(change_set_id: "CS-100", after_command_id: "cmd-other").value!.status).to eq("invalid")
  end

  def create_change_set
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "cmd-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      goal: "Coordinate repositories",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
  end

  def create_work_item
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
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
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events
    event_store.read(
      streams.work_item("W-100"),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
  end
end
