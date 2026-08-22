# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::CreateChangeSet do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      "command_id" => "cmd-100",
      "actor" => { "kind" => "agent", "id" => "planner-1" },
      "change_set_id" => "CS-100",
      "goal" => "Coordinate an API change",
      "acceptance_criteria" => [ "Producer and consumer remain compatible" ]
    }
  end

  it "normalizes valid string-keyed input" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h).to include(command_id: "cmd-100", change_set_id: "CS-100")
    expect(result.to_h.fetch(:actor)).to eq(kind: "agent", id: "planner-1")
  end

  it "rejects unknown fields" do
    result = contract.call(valid_input.merge("status" => "active"))

    expect(result).to be_failure
    expect(result.errors.to_h).to include(status: [ "is not allowed" ])
  end

  it "rejects invalid IDs, blank text, duplicate criteria, and unknown actor kinds" do
    result = contract.call(
      valid_input.merge(
        "command_id" => "bad id",
        "actor" => { "kind" => "robot", "id" => "bad id" },
        "goal" => "   ",
        "acceptance_criteria" => [ "Same", "Same" ]
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h.keys).to contain_exactly(:command_id, :actor, :goal, :acceptance_criteria)
  end
end
