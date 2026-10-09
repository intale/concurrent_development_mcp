# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::CandidateSourceEvent do
  subject(:contract) { described_class.new }

  let(:assignment) do
    {
      event_type: "CandidateWorkIntentionSetAssigned", schema_version: 1,
      stream_context: "DevelopmentIntegration", stream_name: "Candidate",
      stream_id: SecureRandom.uuid_v7, stream_revision: 6, global_position: 7,
      command_id: "candidate-command", actor_kind: "agent", actor_id: "agent-a",
      recorded_by: "coordinator", policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION
    }
  end

  it "decodes current assignment facts independently of the writer's diagnostic policy tag" do
    expect(contract.call(assignment)).to be_success
    expect(contract.call(assignment.merge(policy_version: "diagnostic-writer-policy"))).to be_success
  end

  it "still requires the exact relationship fact schema" do
    expect(contract.call(assignment.merge(schema_version: 2))).to be_failure
  end

  it "requires declared manifest and build-context codec policies to decode their evidence" do
    %w[CandidateChangeManifestCaptured CandidateBuildContextCaptured].each do |type|
      expect(contract.call(assignment.merge(event_type: type, schema_version: 2))).to be_failure
    end
    expect(contract.call(assignment.merge(
      event_type: "CandidateChangeManifestCaptured", schema_version: 2,
      policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA
    ))).to be_success
    expect(contract.call(assignment.merge(
      event_type: "CandidateBuildContextCaptured", schema_version: 2,
      policy_version: Coordinator::Write::Candidates::BuildContextDocumentV1::SCHEMA
    ))).to be_success
  end
end
