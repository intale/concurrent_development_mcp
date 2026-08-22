# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareCreateChangeSet do
  subject(:operation) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-100",
      actor: { kind: "user", id: "user-1" },
      change_set_id: "CS-100",
      goal: "Add coordinated billing change",
      acceptance_criteria: [ "Two agents cannot own the same WorkItem" ]
    }
  end

  it "returns one unwrapped strict command" do
    result = operation.call(input)

    expect(result).to be_success
    expect(result.value!).to be_a(Coordinator::Write::Commands::CreateChangeSet)
    expect(result.value!).not_to be_a(Dry::Monads::Result)
    expect(result.value!.actor).to eq(Coordinator::Write::Commands::Actor.new(kind: "user", id: "user-1"))
  end
end
