# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::AgentChoiceGet, :read_model do
  subject(:query) { described_class.new }

  it "serves the latest available recorded observation without freshness gating" do
    absent = query.call(choice_id: "CHO-choice-query").value!
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "agent_choice_not_observed")

    create(:coordinator_read_agent_choice, choice_id: "CHO-choice-query")
    recorded = query.call(choice_id: "CHO-choice-query").value!

    expect(recorded).to have_attributes(status: "ok")
    expect(recorded.data.choice).to have_attributes(observation_status: "recorded", accepted: nil)
    expect(recorded.data.choice.to_h.keys & %i[fresh pending projection_status]).to be_empty
  end

  it "serves an accepted observation directly from the projection" do
    create(:coordinator_read_agent_choice, :accepted, choice_id: "CHO-choice-accepted")

    result = query.call(choice_id: "CHO-choice-accepted").value!

    expect(result.data.choice).to have_attributes(
      observation_status: "accepted",
      accepted: be_a(Coordinator::Read::AgentChoiceLifecycleEvidenceV1)
    )
  end

  it "returns typed invalid input" do
    result = query.call(choice_id: "bad id").value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end
end
