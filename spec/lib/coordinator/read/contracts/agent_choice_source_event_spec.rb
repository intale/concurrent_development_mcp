# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::AgentChoiceSourceEvent do
  subject(:contract) { described_class.new }

  let(:input) do
    {
      event_type: "AgentChoiceRecorded", schema_version: 2, stream_context: "AgentGovernance",
      stream_name: "AgentChoice", stream_id: SecureRandom.uuid_v7, stream_revision: 0,
      command_id: "cmd-native-choice", actor_kind: "agent", actor_id: "agent-a",
      recorded_by: "coordinator", policy_version: "testing-framework-resolution/v1"
    }
  end

  it "accepts current recording and acceptance with canonical digest metadata" do
    expect(contract.call(input)).to be_success
    accepted = input.merge(
      event_type: "AgentChoiceAccepted", stream_revision: 1, context_digest: "sha256:" + "a" * 64
    )
    expect(contract.call(accepted)).to be_success
    expect(contract.call(accepted.except(:context_digest)).errors.to_h).to have_key(:context_digest)
  end

  it "rejects the superseded schema for both lifecycle facts" do
    expect(contract.call(input.merge(schema_version: 1)).errors.to_h).to have_key(:schema_version)
    expect(contract.call(input.merge(
      event_type: "AgentChoiceAccepted", stream_revision: 1, schema_version: 1
    )).errors.to_h).to have_key(:schema_version)
  end
end
