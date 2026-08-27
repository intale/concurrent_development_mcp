# frozen_string_literal: true

RSpec.describe "Development Artifact contracts" do
  let(:capture) { Coordinator::Write::Contracts::CaptureDevelopmentArtifact.new }
  let(:capture_batch) { Coordinator::Write::Contracts::DevelopmentArtifactCaptureBatch.new }
  let(:relation) { Coordinator::Write::Contracts::DeclareDevelopmentArtifactRelation.new }
  let(:relation_batch) { Coordinator::Write::Contracts::DevelopmentArtifactRelationDeclareBatch.new }

  it "accepts canonical UTF-8 and binary content while rejecting unknown keys and noncanonical Base64" do
    expect(capture.call(capture_input)).to be_success
    expect(capture.call(capture_input(content: binary_content))).to be_success
    expect(capture.call(capture_input.merge(extra: true))).to be_failure
    expect(
      capture.call(capture_input(content: binary_content.merge(base64: "YQ==\n")))
    ).to be_failure
  end

  it "enforces the external-reference URL representation exactly" do
    valid = capture_input(
      kind: "external_reference",
      content: { encoding: "utf-8", media_type: "text/uri-list", text: "https://example.test/a\n" },
      source: source.merge(kind: "web_page", locator: "https://example.test/a")
    )

    expect(capture.call(valid)).to be_success
    expect(capture.call(valid.merge(content: valid.fetch(:content).merge(text: "other\n")))).to be_failure
  end

  it "enforces graph semantics, link evidence, target compatibility, and supersession input" do
    source_id = "artifact:v1:#{'a' * 64}"
    target_id = "artifact:v1:#{'b' * 64}"
    valid = relation_input(source_id:, target_id:)

    expect(relation.call(valid)).to be_success
    expect(
      relation.call(
        valid.merge(
          attributes: {
            path: "../guide.md",
            fragment: "install",
            normalized_locator: "guide.md"
          },
          supersedes: {
            relation_id: "artifact-relation:v1:#{'c' * 64}",
            reason: "wrong target"
          }
        )
      )
    ).to be_success
    expect(
      relation.call(valid.merge(relation: "documents", attributes: { path: "a.md", fragment: "part" }))
    ).to be_failure
    expect(relation.call(valid.merge(attributes: { fragment: "install" }))).to be_failure
    expect(relation.call(valid.merge(attributes: { path: "/a.md" }))).to be_failure
    expect(relation.call(valid.merge(attributes: { path: "a.md#part" }))).to be_failure
    expect(
      relation.call(valid.merge(relation: "contains", target: { kind: "repository", id: "repo-1" }, attributes: {}))
    ).to be_failure
    expect(
      relation.call(valid.merge(target: { kind: "artifact", id: "not-an-artifact" }))
    ).to be_failure
    expect(relation.call(valid.merge(target: { kind: "artifact", id: source_id }))).to be_failure
    expect(relation.call(valid.merge(target: valid.fetch(:target).merge(extra: true)))).to be_failure
  end

  it "accepts the complete single-relation contract in each batch item" do
    item = relation_input(
      source_id: "artifact:v1:#{'a' * 64}",
      target_id: "artifact:v1:#{'b' * 64}"
    ).merge(
      attributes: {
        path: "../guide.md",
        fragment: "install",
        normalized_locator: "guide.md"
      },
      supersedes: {
        relation_id: "artifact-relation:v1:#{'c' * 64}",
        reason: "wrong target"
      }
    )
    input = {
      command_id: "cmd-contract-relation-batch",
      actor: { kind: "agent", id: "agent-1" },
      batch_id: SecureRandom.uuid_v7,
      items: [ item ]
    }

    expect(relation_batch.call(input)).to be_success
    expect(relation_batch.call(input.merge(items: [ item.merge(extra: true) ]))).to be_failure
  end

  it "reserves internal command identities across both Artifact Batch contracts" do
    capture_item = capture_input(command_id: "internal:artifact:item")
    capture_input_batch = {
      command_id: "cmd-contract-artifact-batch",
      actor: { kind: "agent", id: "agent-1" },
      batch_id: SecureRandom.uuid_v7,
      items: [ capture_item ]
    }
    relation_item = relation_input(
      source_id: "artifact:v1:#{'a' * 64}",
      target_id: "artifact:v1:#{'b' * 64}"
    ).merge(command_id: "internal:relation:item")
    relation_input_batch = {
      command_id: "cmd-contract-relation-batch",
      actor: { kind: "agent", id: "agent-1" },
      batch_id: SecureRandom.uuid_v7,
      items: [ relation_item ]
    }

    expect(capture_batch.call(capture_input_batch).errors.to_h).to have_key(:items)
    expect(relation_batch.call(relation_input_batch).errors.to_h).to have_key(:items)
    expect(
      capture_batch.call(capture_input_batch.merge(command_id: "internal:artifact:batch")).errors.to_h
    ).to have_key(:command_id)
    expect(
      relation_batch.call(relation_input_batch.merge(command_id: "internal:relation:batch")).errors.to_h
    ).to have_key(:command_id)
  end

  def capture_input(**overrides)
    {
      command_id: "cmd-contract-artifact",
      actor: { kind: "agent", id: "agent-1" },
      scope: "project:alpha",
      title: "Artifact",
      kind: "documentation",
      labels: %w[docs],
      content: { encoding: "utf-8", media_type: "text/plain", text: "hello\n" },
      source:
    }.merge(overrides)
  end

  def source
    {
      kind: "local_file",
      locator: "README.md",
      revision: nil,
      observed_at: "2026-08-25T16:00:00.000000Z",
      collector: "spec/v1"
    }
  end

  def binary_content
    {
      encoding: "binary",
      media_type: "application/octet-stream",
      base64: [ "a" ].pack("m0")
    }
  end

  def relation_input(source_id:, target_id:)
    {
      command_id: "cmd-contract-relation",
      actor: { kind: "agent", id: "agent-1" },
      source_artifact_id: source_id,
      relation: "references",
      target: { kind: "artifact", id: target_id },
      attributes: { path: "docs/a.md" }
    }
  end
end
