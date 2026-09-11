# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::DecisionInterpretationSourceEvent do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      event_type: "DecisionInterpretationProposed",
      schema_version: 1,
      stream_context: "HumanGuidance",
      stream_name: "Interpretation",
      stream_id: "M-1",
      stream_revision: 0,
      actor_kind: "agent",
      actor_id: "classifier-host"
    }
  end

  it "accepts all modeled lifecycle facts only on an Interpretation source" do
    described_class::EVENT_TYPES.each do |event_type|
      expect(contract.call(valid_input.merge(event_type:))).to be_success
    end
  end

  it "rejects another type, stream, schema, actor, revision, or identifier" do
    result = contract.call(
      valid_input.merge(
        event_type: "DecisionActivated",
        schema_version: 2,
        stream_context: "DevelopmentPlanning",
        stream_name: "Decision",
        stream_id: "bad id",
        stream_revision: -1,
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
      :stream_revision,
      :actor_kind,
      :actor_id
    )
    expect(contract.call(valid_input.merge(schema_version: 3)).errors.to_h).to have_key(:schema_version)
  end
end
