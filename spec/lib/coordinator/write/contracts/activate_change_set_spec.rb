# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::ActivateChangeSet do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      "command_id" => "cmd-250",
      "actor" => { "kind" => "agent", "id" => "planner-1" },
      "change_set_id" => "CS-100"
    }
  end

  it "normalizes the strict public activation input" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h).to eq(
      command_id: "cmd-250",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100"
    )
  end

  it "rejects unknown keys and invalid identifiers" do
    unknown = contract.call(valid_input.merge("status" => "active"))
    invalid = contract.call(
      valid_input.merge(
        "command_id" => "bad id",
        "actor" => { "kind" => "agent", "id" => "bad id" },
        "change_set_id" => "?"
      )
    )

    expect(unknown).to be_failure
    expect(unknown.errors.to_h).to have_key(:status)
    expect(invalid).to be_failure
    expect(invalid.errors.to_h.keys).to contain_exactly(:command_id, :actor, :change_set_id)
  end
end
