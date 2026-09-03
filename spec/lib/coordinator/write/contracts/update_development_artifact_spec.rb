# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::UpdateDevelopmentArtifact do
  subject(:contract) { described_class.new }

  let(:base) do
    {
      command_id: "cmd-artifact-update",
      actor: { kind: "agent", id: "agent-1" },
      artifact_id: "018f0f4d-4e45-7abc-8def-000000000171",
      expected_revision: 2,
      changes: { title: "Updated title" }
    }
  end

  it "requires at least one known change and validates UUIDv7/revision" do
    expect(contract.call(base)).to be_success
    expect(contract.call(base.merge(changes: {}))).to be_failure
    expect(contract.call(base.merge(artifact_id: "not-a-uuid"))).to be_failure
    expect(contract.call(base.merge(expected_revision: -1))).to be_failure
    expect(contract.call(base.merge(changes: { title: "Updated", extra: true }))).to be_failure
  end

  it "accepts UTF-8 and binary content using the same content boundary as capture" do
    expect(
      contract.call(base.merge(changes: {
        content: { encoding: "utf-8", media_type: "text/plain", text: "hello" }
      }))
    ).to be_success
    expect(
      contract.call(base.merge(changes: {
        content: { encoding: "binary", media_type: "application/octet-stream", base64: "AP8=" }
      }))
    ).to be_success
    expect(
      contract.call(base.merge(changes: {
        content: { encoding: "utf-8", media_type: "text/plain", text: "hello", base64: "aA==" }
      }))
    ).to be_failure
  end
end
