# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionGet, :read_model do
  subject(:query) { described_class.new }

  it "serves the latest available recorded Decision without freshness claims" do
    absent = query.call(decision_id: "D-query").value!
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "decision_not_observed")

    create(:coordinator_read_decision_definition, decision_id: "D-query")
    recorded = query.call(decision_id: "D-query").value!

    expect(recorded).to have_attributes(status: "ok")
    expect(recorded.data.decision).to have_attributes(policy_status: "recorded", activated: nil)
    expect(recorded.to_h.keys & %i[active fresh pending projection_status stream_revision]).to be_empty
  end

  it "serves an active Decision and its exact projected slot" do
    row = create(:coordinator_read_decision_definition, :active, decision_id: "D-active")

    result = query.call(decision_id: "D-active").value!

    expect(result.data.decision).to have_attributes(
      policy_status: "active",
      slot: have_attributes(slot_id: row.slot.fetch("slot_id"))
    )
    expect(result.data.decision.current_head.event.type).to eq("DecisionActivated")
  end

  it "returns typed invalid input" do
    result = query.call(decision_id: "bad id").value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end
end
