# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareCompleteWorkItem do
  subject(:prepare) { described_class.new }

  it "builds one immutable command and canonically orders attributed outputs" do
    result = prepare.call(
      command_id: "cmd-complete-1",
      actor: { kind: "agent", id: "agent-7" },
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-1",
      candidate_id: "CAN-1",
      produced_outputs: [
        { kind: "contract", key: "payments-v2" },
        { kind: "artifact", key: "billing-gem" }
      ]
    )

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      command_id: "cmd-complete-1",
      actor: have_attributes(kind: "agent", id: "agent-7"),
      candidate_id: "CAN-1",
      produced_outputs: [
        have_attributes(kind: "artifact", key: "billing-gem"),
        have_attributes(kind: "contract", key: "payments-v2")
      ]
    )
    expect(result.value!).to be_frozen
  end

  it "returns a modeled invalid-input outcome" do
    result = prepare.call(command_id: "bad id")

    expect(result.failure).to have_attributes(
      code: :invalid_input,
      message: "CompleteWorkItem input is invalid"
    )
  end
end
