# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CommandReceiptsV1, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:projector) { described_class.new }

  it "stores a validated completion once and exposes the typed projected receipt" do
    completion = Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "cmd-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      goal: "Coordinate repositories",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
    event = command_event("cmd-100")

    projector.call(event)
    projector.call(event)

    projected = Coordinator::Read::Repositories::CommandReceipts.new.fetch("cmd-100")
    expect(projected).to eq(completion)
    expect(Coordinator::Read::CommandReceipt.count).to eq(1)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "command_receipts").count).to eq(1)
  end

  def command_event(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    ).sole
  end
end
