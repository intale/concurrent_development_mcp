# frozen_string_literal: true

RSpec.describe Coordinator::Read::OperationBatchArguments do
  subject(:builder) { described_class.new }

  let(:input_digest) { Coordinator::Write::CommandInputDigest.new }

  it "reconstructs exact public Skill arguments without server-derived identity or digests" do
    input = {
      command_id: "skill-command",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Review a change",
      instructions: "Inspect the complete diff.",
      assets: [
        {
          path: "bin/check",
          executable: true,
          content: {
            encoding: "utf-8",
            media_type: "text/x-shellscript",
            text: "#!/bin/sh\n"
          }
        }
      ]
    }
    command = Coordinator::Write::Operations::PreparePublishSkillRevision.new.call(input).value!

    expect(builder.call(input_digest.document(command))).to eq(input)
  end

  it "reconstructs exact public UTF-8 Artifact arguments from canonical bytes" do
    input = {
      command_id: "artifact-command",
      actor: { kind: "agent", id: "agent-1" },
      scope: "project:alpha",
      title: "README",
      kind: "documentation",
      labels: %w[docs imported],
      content: { encoding: "utf-8", media_type: "text/plain", text: "héllo\n" },
      source: {
        kind: "local_file",
        locator: "README.md",
        revision: nil,
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "spec/v1"
      }
    }
    command = Coordinator::Write::Operations::PrepareCaptureDevelopmentArtifact.new.call(input).value!

    expect(builder.call(input_digest.document(command))).to eq(input)
  end

  it "reconstructs exact public relation arguments without the derived relation identity" do
    input = {
      command_id: "relation-command",
      actor: { kind: "agent", id: "agent-1" },
      source_artifact_id: "artifact:v1:#{'a' * 64}",
      relation: "references",
      target: { kind: "artifact", id: "artifact:v1:#{'b' * 64}" },
      attributes: {
        path: "docs/guide.md",
        fragment: "install",
        normalized_locator: "docs/guide.md"
      },
      supersedes: {
        relation_id: "artifact-relation:v1:#{'c' * 64}",
        reason: "wrong link"
      }
    }
    command = Coordinator::Write::Operations::PrepareDeclareDevelopmentArtifactRelation.new.call(input).value!

    expect(builder.call(input_digest.document(command))).to eq(input)
  end
end
