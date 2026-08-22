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

  it "accepts both modeled facts only on an Interpretation source" do
    expect(contract.call(valid_input)).to be_success
    expect(
      contract.call(valid_input.merge(event_type: "DecisionClarificationRequired"))
    ).to be_success
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
      :schema_version,
      :stream_context,
      :stream_name,
      :stream_id,
      :stream_revision,
      :actor_kind,
      :actor_id
    )
  end
end
