# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::OperationGet, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:projector) { Coordinator::Read::Projectors::CommandReceiptsV1.new }

  subject(:query) { described_class.new }

  it "serves only the latest available receipt projection without a write-store fallback" do
    completion = create_change_set

    expect(query.call(command_id: "cmd-100").value!.status).to eq("not_found")

    projector.call(command_completion_event("cmd-100"))
    observed = query.call(command_id: "cmd-100").value!

    expect(observed.status).to eq("ok")
    expect(observed.data.result).to eq(completion.data)
    expect(observed.data.emitted_events).to eq(completion.emitted_events)
    expect(observed.to_h).not_to include(:projection_status)
  end

  it "returns a projected receipt while coordination-context projectors have processed nothing" do
    create_change_set
    completion = create_work_item

    projector.call(command_completion_event("cmd-200"))
    observed = query.call(command_id: "cmd-200").value!

    expect(observed.status).to eq("ok")
    expect(observed.data.result).to eq(completion.data)
    expect(Coordinator::Read::CoordContext.count).to eq(0)
  end

  it "returns not_found and typed invalid input without an unbounded read" do
    expect(query.call(command_id: "cmd-404").value!.status).to eq("not_found")
    expect(query.call(command_id: "bad id").value!.status).to eq("invalid")
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
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "cmd-200",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Implement billing",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
  end

  def command_completion_event(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    ).sole
  end
end
