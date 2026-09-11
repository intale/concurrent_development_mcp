# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::GuidanceSourceEvent do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      event_type: "UserUtteranceRecorded",
      schema_version: 2,
      stream_context: "HumanGuidance",
      stream_name: "Conversation",
      stream_id: "C-1",
      stream_revision: 0,
      actor_kind: "agent",
      actor_id: "host-1"
    }
  end

  it "accepts cohesive utterance and anchor facts only on a Conversation source" do
    expect(contract.call(valid_input)).to be_success
    expect(
      contract.call(valid_input.merge(event_type: "UserUtteranceForwardedByAgent"))
    ).to be_success
    expect(
      contract.call(valid_input.merge(event_type: "GuidanceMessageAnchored", schema_version: 1))
    ).to be_success
  end

  it "rejects another type, stream, schema, actor, or identifier" do
    result = contract.call(
      valid_input.merge(
        event_type: "DecisionActivated",
        schema_version: 1,
        stream_context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        stream_id: "bad id",
        actor_kind: "robot",
        actor_id: "bad id"
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h.keys).to contain_exactly(
      :event_type,
      :stream_context,
      :stream_name,
      :stream_id,
      :actor_kind,
      :actor_id
    )
    expect(contract.call(valid_input.merge(schema_version: 3)).errors.to_h).to have_key(:schema_version)
  end
end
