# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareActivateChangeSet do
  subject(:operation) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-250",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100"
    }
  end

  it "constructs one immutable strict command" do
    result = operation.call(input)

    expect(result).to be_success
    expect(result.value!).to eq(
      Coordinator::Write::Commands::ActivateChangeSet.new(
        command_id: "cmd-250",
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
        change_set_id: "CS-100"
      )
    )
    expect(result.value!).to be_frozen
  end

  it "returns dry-validation errors as an invalid-input outcome" do
    result = operation.call(input.merge(change_set_id: "bad id"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:invalid_input)
    expect(result.failure.details).to have_key(:change_set_id)
  end
end
