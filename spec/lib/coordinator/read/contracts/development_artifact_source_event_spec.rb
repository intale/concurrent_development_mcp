# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::DevelopmentArtifactSourceEvent do
  subject(:contract) { described_class.new }

  let(:artifact_id) { "018f0f4d-4e45-7abc-8def-000000000191" }
  let(:relation_id) { "018f0f4d-4e45-7abc-8def-000000000192" }
  let(:base) do
    {
      event_type: "DevelopmentArtifactRelationDeclared",
      schema_version: 1,
      stream_context: "DevelopmentMemory",
      stream_name: "DevelopmentArtifact",
      stream_id: artifact_id,
      stream_revision: 1,
      global_position: 1,
      command_id: "command-1",
      actor_kind: "agent",
      actor_id: "agent-1",
      recorded_by: "coordinator",
      policy_version: "development-artifact-repository/v1"
    }
  end

  it "accepts legacy relation facts on the artifact stream" do
    expect(contract.call(base)).to be_success
  end

  it "accepts current relation facts on their dedicated relation stream" do
    result = contract.call(
      base.merge(
        schema_version: 2,
        stream_name: "DevelopmentArtifactRelation",
        stream_id: relation_id,
        policy_version: "development-artifact-repository/v2"
      )
    )

    expect(result).to be_success
  end

  it "rejects a legacy relation fact on the relation stream" do
    result = contract.call(base.merge(stream_name: "DevelopmentArtifactRelation"))

    expect(result).to be_failure
  end
end
