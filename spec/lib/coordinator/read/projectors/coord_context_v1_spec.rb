# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CoordContextV1, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:projector) { described_class.new }

  it "atomically projects exact source identities and ignores duplicate delivery" do
    create_change_set("CS-100")
    create_work_item("CS-100", "W-100")
    change_set_events = change_set_events("CS-100")
    work_item_event = work_item_events("W-100").sole

    change_set_events.first(2).each { projector.call(_1) }
    projector.call(change_set_events.find { _1.type == "WorkItemAddedToChangeSet" })
    projector.call(work_item_event)
    projector.call(work_item_event)

    snapshot = Coordinator::Read::Repositories::CoordContexts.new.resolve(
      scope_kind: "work_item",
      scope_id: "W-100"
    )
    expect(snapshot.state.change_set.to_h).to include(
      change_set_id: "CS-100",
      goal: "Coordinate CS-100",
      acceptance_criteria: [ "Agents do not overlap" ]
    )
    expect(snapshot.state.work_item_ids).to eq([ "W-100" ])
    expect(snapshot.state.work_items.sole.to_h).to include(
      work_item_id: "W-100",
      repository_id: "billing",
      status: "planned"
    )
    expect(snapshot.source_positions.length).to eq(2)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "coord_context").count).to eq(4)
  end

  it "converges when cross-stream WorkItem siblings arrive in either order" do
    create_change_set("CS-100")
    create_work_item("CS-100", "W-100")
    change_set_events("CS-100").first(2).each { projector.call(_1) }

    membership = change_set_events("CS-100").find { _1.type == "WorkItemAddedToChangeSet" }
    details = work_item_events("W-100").sole
    projector.call(membership)
    projector.call(details)
    first_document = Coordinator::Read::CoordContext.find("CS-100").document

    ReadModelTestSafety.clean!
    change_set_events("CS-100").first(2).each { projector.call(_1) }
    projector.call(details)
    projector.call(membership)

    expect(Coordinator::Read::CoordContext.find("CS-100").document).to eq(first_document)
  end

  it "projects activation, readiness, ownership, and exact Attempt bases" do
    create_change_set("CS-100")
    create_work_item("CS-100", "W-100")
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "activate-CS-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100"
    ).value!
    activation = change_set_events("CS-100").find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
      command_id: "acquire-W-100",
      actor: { kind: "agent", id: "agent-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100",
      base_snapshots: [
        { repository_id: "billing", commit_oid: "a" * 40 }
      ]
    ).value!

    planning = change_set_events("CS-100")
    work = work_item_events("W-100")
    attempt = event_store.read(
      streams.attempt("A-100"),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_ACQUISITION
    )
    [ planning[0], planning[1], work[0], planning[2], planning[3], work[1], work[2], *attempt ].each do |event|
      projector.call(event)
    end

    snapshot = Coordinator::Read::Repositories::CoordContexts.new.resolve(
      scope_kind: "attempt",
      scope_id: "A-100"
    )
    expect(snapshot.state.change_set.status).to eq("active")
    expect(snapshot.state.work_items.sole.to_h).to include(
      status: "acquired",
      active_attempt_id: "A-100",
      active_agent_id: "agent-1"
    )
    expect(snapshot.state.attempts.sole.to_h).to include(
      attempt_id: "A-100",
      status: "started",
      base_snapshots: [
        { repository_id: "billing", object_format: "sha1", commit_oid: "a" * 40 }
      ]
    )
  end

  def create_change_set(change_set_id)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "create-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate #{change_set_id}",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
  end

  def create_work_item(change_set_id, work_item_id)
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id: "billing",
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
  end
end
