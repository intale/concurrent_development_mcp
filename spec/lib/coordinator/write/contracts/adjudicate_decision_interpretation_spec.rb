# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::AdjudicateDecisionInterpretation do
  subject(:contract) { described_class.new }

  it "accepts each strict adjudication action" do
    accept = contract.call(InterpretationInput.adjudication)
    reject = contract.call(InterpretationInput.adjudication(action: "reject"))
    clarification = contract.call(
      InterpretationInput.adjudication(
        action: "request_clarification",
        clarification: InterpretationInput.clarification
      )
    )

    expect([ accept, reject, clarification ]).to all(be_success)
  end

  it "implements GDN-03-SHAPE-01" do
    missing = contract.call(
      InterpretationInput.adjudication(action: "request_clarification", clarification: nil)
    )
    extraneous = contract.call(
      InterpretationInput.adjudication(action: "accept", clarification: InterpretationInput.clarification)
    )
    empty = contract.call(
      InterpretationInput.adjudication(
        action: "request_clarification",
        clarification: InterpretationInput.clarification.merge(questions: [])
      )
    )

    expect([ missing, extraneous, empty ]).to all(be_failure)
    expect(missing.errors.to_h).to have_key(:clarification)
    expect(extraneous.errors.to_h).to have_key(:clarification)
    expect(empty.errors.to_h.dig(:clarification)).to have_key(:questions)
  end

  it "rejects unknown keys and invalid bounded rationale evidence" do
    result = contract.call(
      InterpretationInput.adjudication.merge(
        rationale: { code: "bad code", summary: "\u0000" },
        decision_id: "D-1"
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h).to include(:rationale, :decision_id)
  end
end
