# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::AgentChoiceGet, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:projector) { Coordinator::Read::Projectors::AgentChoicesV1.new }

  it "serves every latest available observation without consulting write authority" do
    recorded, accepted = AgentChoiceScenario.record_no_policy_choice(
      prefix: "choice-query"
    ).fetch(:events)

    absent = query.call(choice_id: "CHO-choice-query").value!
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "agent_choice_not_observed")

    projector.call(recorded)
    recorded_result = query.call(choice_id: "CHO-choice-query").value!
    expect(recorded_result).to have_attributes(status: "ok")
    expect(recorded_result.data.choice).to have_attributes(
      observation_status: "recorded",
      accepted: nil
    )

    projector.call(accepted)
    accepted_result = query.call(choice_id: "CHO-choice-query").value!
    expect(accepted_result.data.choice).to have_attributes(
      observation_status: "accepted",
      accepted: be_a(Coordinator::Read::AgentChoiceLifecycleEvidenceV1)
    )
    expect(accepted_result.data.choice.to_h.keys & %i[fresh pending projection_status]).to be_empty
  end

  it "returns typed invalid input without reading pg_eventstore" do
    result = query.call(choice_id: "bad id").value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end
end
