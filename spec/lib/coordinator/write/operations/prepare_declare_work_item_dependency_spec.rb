# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareDeclareWorkItemDependency do
  subject(:operation) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-230",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_artifact",
      required_output: { kind: "artifact", key: "openapi-v1" }
    }
  end

  it "constructs the strict command and nested dry struct" do
    result = operation.call(input)

    expect(result).to be_success
    command = result.value!
    expect(command).to be_a(Coordinator::Write::Commands::DeclareWorkItemDependency)
    expect(command.required_output).to be_a(Coordinator::Write::RequiredOutput)
    expect(command.to_h).to eq(input)
    expect(command).to be_frozen
    expect(command.required_output).to be_frozen
  end

  it "returns stable invalid-input details" do
    result = operation.call(input.merge(dependency_kind: "whenever"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:invalid_input)
    expect(result.failure.details).to have_key(:dependency_kind)
  end
end
