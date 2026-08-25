# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::CompleteWorkItem do
  subject(:contract) { described_class.new }

  it "accepts a final-Candidate completion with attributed outputs" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h).to eq(valid_input)
  end

  it "accepts a completion that produces no named outputs" do
    expect(contract.call(valid_input(produced_outputs: []))).to be_success
  end

  it "rejects unknown keys, duplicate outputs, unsupported output kinds, and malformed identifiers" do
    cases = [
      valid_input.merge(unmodeled: true),
      valid_input(produced_outputs: [ output, output ]),
      valid_input(produced_outputs: [ output(kind: "package") ]),
      valid_input(candidate_id: "candidate id")
    ]

    cases.each { expect(contract.call(_1)).to be_failure }
  end

  it "rejects more than the bounded output count" do
    outputs = (Coordinator::Shared::Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT + 1).times.map do |index|
      output(key: "artifact-#{index}")
    end

    expect(contract.call(valid_input(produced_outputs: outputs))).to be_failure
  end

  def valid_input(**overrides)
    {
      command_id: "cmd-complete-1",
      actor: { kind: "agent", id: "agent-7" },
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-1",
      candidate_id: "CAN-1",
      produced_outputs: [ output ]
    }.merge(overrides)
  end

  def output(kind: "artifact", key: "billing-gem")
    { kind:, key: }
  end
end
