# frozen_string_literal: true

RSpec.describe Coordinator::Contracts::CreateWorkItem do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      "command_id" => "cmd-200",
      "actor" => { "kind" => "agent", "id" => "planner-1" },
      "change_set_id" => "CS-100",
      "work_item_id" => "W-200",
      "repository_id" => "billing",
      "goal" => "Implement capture validation",
      "acceptance_criteria" => [ "Reject duplicate ownership" ]
    }
  end

  it "normalizes the frozen public input contract" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h).to eq(
      command_id: "cmd-200",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    )
  end

  it "rejects unknown fields" do
    result = contract.call(valid_input.merge("competitive_mode" => true))

    expect(result).to be_failure
    expect(result.errors.to_h).to have_key(:competitive_mode)
  end

  it "rejects invalid identifiers and repository slugs" do
    result = contract.call(
      valid_input.merge(
        "command_id" => " invalid",
        "change_set_id" => "?",
        "work_item_id" => "W 200",
        "repository_id" => "Billing/API"
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h.keys).to include(:command_id, :change_set_id, :work_item_id, :repository_id)
  end

  it "rejects blank text, duplicate criteria, and out-of-bound criteria" do
    duplicate = contract.call(valid_input.merge("goal" => " \n", "acceptance_criteria" => [ "same", "same" ]))
    too_many = contract.call(valid_input.merge("acceptance_criteria" => Array.new(51) { |index| "criterion-#{index}" }))

    expect(duplicate).to be_failure
    expect(duplicate.errors.to_h.keys).to include(:goal, :acceptance_criteria)
    expect(too_many).to be_failure
    expect(too_many.errors.to_h).to have_key(:acceptance_criteria)
  end
end
