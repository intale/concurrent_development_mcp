# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareCreateWorkItem do
  subject(:operation) { described_class.new }

  let(:repository_id) { "018f22a2-7b9c-7def-8abc-1234567890ab" }
  let(:input) do
    {
      command_id: "cmd-200",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id:,
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    }
  end

  it "returns one deeply immutable strict command" do
    result = operation.call(input)

    expect(result).to be_success
    command = result.value!
    expect(command).to be_a(Coordinator::Write::Commands::CreateWorkItem)
    expect(command.to_h).to eq(input)
    expect(command.actor).to be_a(Coordinator::Write::Commands::Actor)
    expect(command).to be_frozen
    expect(command.actor).to be_frozen
    expect(command.acceptance_criteria).to be_frozen
  end

  it "returns typed invalid-input details without constructing a command" do
    result = operation.call(input.merge(repository_id: "billing"))

    expect(result).to be_failure
    expect(result.failure).to be_a(Coordinator::Write::OutcomeError)
    expect(result.failure.code).to eq(:invalid_input)
    expect(result.failure.details).to have_key(:repository_id)
  end
end
