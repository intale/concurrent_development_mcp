# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::TargetCompletionLoader, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }
  let(:command) do
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-target-completion-loader",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-target-completion-loader",
      goal: "Recover a committed target outcome",
      acceptance_criteria: [ "The completion is reconstructable from its command stream" ]
    )
  end

  subject(:loader) do
    described_class.new(
      event_store:,
      schema_registry: schemas,
      stream_factory: streams
    )
  end

  it "returns no completion when the bounded command stream is empty" do
    expect(loader.call(command.command_id)).to be_nil
  end

  it "loads the physical completion and typed payload from the bounded command stream" do
    expected = Coordinator::Write::Operations::ExecuteCreateChangeSet.new(
      event_store:,
      schema_registry: schemas,
      stream_factory: streams,
      event_factory: Coordinator::Write::EventFactory.new(registry: schemas)
    ).call_command(command).value!

    completion = loader.call(command.command_id)

    expect(completion.payload).to eq(expected)
    expect(completion.event.type).to eq("CommandCompleted")
  end
end
