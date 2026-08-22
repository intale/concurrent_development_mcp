# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::ActivateDecision do
  subject(:contract) { described_class.new }

  it "normalizes the strict activation input" do
    result = contract.call(InterpretationInput.activation.transform_keys(&:to_s))

    expect(result).to be_success
    expect(result.to_h).to eq(InterpretationInput.activation)
  end

  it "rejects unknown keys and invalid identifiers or rationale text" do
    result = contract.call(
      InterpretationInput.activation.merge(
        decision_id: "bad id",
        rationale: { code: "bad code", summary: "\u0000" },
        source_message_id: "M-1"
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h).to include(:decision_id, :rationale, :source_message_id)
  end
end
