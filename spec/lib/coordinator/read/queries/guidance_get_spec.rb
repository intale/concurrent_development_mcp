# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::GuidanceGet, :read_model do
  subject(:query) { described_class.new }

  it "serves only the available projection and honestly reports absence" do
    absent = query.call(message_id: "M-query").value!
    expect(absent.status).to eq("not_found")
    expect(absent.data.code).to eq("guidance_not_observed")

    create(
      :coordinator_read_user_utterance,
      message_id: "M-query",
      conversation_id: "C-query",
      text: "This was forwarded without authenticated provenance."
    )
    observed = query.call(message_id: "M-query").value!

    expect(observed.status).to eq("ok")
    expect(observed.data.guidance.to_h).to include(
      message_id: "M-query",
      source: "agent_forwarded",
      policy_status: "evidence_only"
    )
    expect(observed.to_h.keys & %i[active fresh pending projection_status]).to be_empty
  end

  it "returns typed invalid input" do
    result = query.call(message_id: "bad id").value!

    expect(result.status).to eq("invalid")
    expect(result.data.code).to eq("invalid_input")
  end
end
