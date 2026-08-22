# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::CorrectDecision do
  subject(:contract) { described_class.new }

  let(:head) do
    {
      event_id: "01900000-0000-7000-8000-000000000001",
      type: "DecisionActivated",
      stream_context: "HumanGuidance",
      stream_name: "Decision",
      stream_id: "D-1",
      stream_revision: 1
    }
  end

  it "accepts the strict DEC-02A public command shape" do
    result = contract.call(InterpretationInput.correction(expected_head: head))

    expect(result).to be_success
  end

  it "rejects a predecessor from another Decision" do
    result = contract.call(
      InterpretationInput.correction(expected_head: head.merge(stream_id: "D-2"))
    )

    expect(result).to be_failure
    expect(result.errors.to_h.dig(:expected_head, :stream_id)).to include("must equal decision_id")
  end

  it "rejects unknown keys and non-lifecycle predecessor types" do
    result = contract.call(
      InterpretationInput.correction(
        expected_head: head.merge(type: "DecisionRecorded")
      ).merge(definition: {})
    )

    expect(result).to be_failure
    expect(result.errors.to_h).to include(:definition, :expected_head)
  end
end
